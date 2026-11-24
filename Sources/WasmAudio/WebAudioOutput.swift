//
//  WebAudioOutput.swift
//  NucleantAudio
//
//  Web Audio, through JavaScriptKit: an AudioWorkletNode plays what it is sent
//  on the browser's audio thread, and reports how many frames it took; the
//  output answers by rendering that many more and sending them, so `lead`
//  seconds are always on their way. The module itself stays on the page's one
//  thread, so the renderer runs there, between the module's other calls.
//
//  The worklet's processor is the one piece in JavaScript (`worklet` below):
//  it runs in the audio thread's own scope, which the module cannot reach.
//
//  At 48 kHz, as Linux's output is: the rate the AudioContext is made at, the
//  browser converting if the device runs at another. Browsers start no sound
//  before the page has had a user gesture, so a context held back until then
//  starts at the first pointer, touch or key press.
//

import AudioProtocols
import JavaScriptKit

public final class WebAudioOutput<Renderer: AudioRenderer>: AudioOutput {
    public let sampleRate: Double
    private let channels: Int
    private let renderer: Renderer
    /// One chunk's frames, rendered here and copied into the chunk sent.
    private let buffer: UnsafeMutableBufferPointer<Float>

    /// Made at the first `start`, so a page that never plays never asks.
    private var context: JSObject?
    private var moduleLoaded = false
    private var node: JSObject?
    private var playing = false
    /// Frames sent and not yet reported played.
    private var queued = 0
    private var onMessage: JSClosure?
    private var onGesture: JSClosure?

    public init(channels: Int, renderer: Renderer) throws {
        guard JSObject.global.AudioContext.function != nil, JSObject.global.AudioWorkletNode.function != nil else {
            throw AudioPlayerError.outputUnavailable("this browser has no Web Audio (AudioContext with AudioWorklet)")
        }
        sampleRate = Self.preferredRate
        self.channels = channels
        self.renderer = renderer
        buffer = .allocate(capacity: Self.capacity * channels)
        buffer.initialize(repeating: 0)
    }

    deinit {
        stop()
        stopWaitingForGesture()
        _ = context?.close!()
        buffer.deallocate()
    }

    public func start() throws {
        guard !playing else { return }
        playing = true
        guard let context else {
            makeContext()
            return
        }
        resumeWhenAllowed()
        if moduleLoaded { connect(to: context) }
    }

    public func stop() {
        guard playing else { return }
        playing = false
        if let node {
            node.port.onmessage = .null
            _ = node.port.postMessage("stop")
            _ = node.disconnect!()
        }
        node = nil
        onMessage = nil
        queued = 0
        // Nothing playing through it: the audio thread can rest.
        _ = context?.suspend!()
    }

    // MARK: Context

    private func makeContext() {
        let options = JSObject()
        options.sampleRate = .number(sampleRate)
        options.latencyHint = "interactive"
        let context = JSObject.global.AudioContext.function!.new(options)
        self.context = context
        resumeWhenAllowed()

        let type = JSObject()
        type.type = "text/javascript"
        let source = JSObject.global.Blob.function!.new([Self.worklet], type)
        let url = JSObject.global.URL.createObjectURL(source)
        let loading = JSPromise(context.audioWorklet.addModule(url).object!)!
        loading.then(
            success: { [weak self] _ in
                _ = JSObject.global.URL.revokeObjectURL(url)
                guard let self else { return .undefined }
                moduleLoaded = true
                if playing { connect(to: context) }
                return .undefined
            },
            failure: { error in
                _ = JSObject.global.console.error("[NucleantAudio] the output could not start:", error)
                return .undefined
            }
        )
    }

    /// Runs the context now if the page may, else from its next user gesture.
    private func resumeWhenAllowed() {
        guard let context, context.state.string != "running", onGesture == nil else { return }
        let attempt = JSClosure { [weak self] _ in
            self?.attemptResume()
            return .undefined
        }
        onGesture = attempt
        for type in Self.gestures {
            _ = JSObject.global.document.addEventListener(type, attempt, true)
        }
        attemptResume()
    }

    private func attemptResume() {
        guard let context, let resuming = JSPromise(context.resume!().object!) else { return }
        resuming.then(
            success: { [weak self] _ in
                if self?.context?.state.string == "running" { self?.stopWaitingForGesture() }
                return .undefined
            },
            failure: { _ in .undefined }
        )
    }

    private func stopWaitingForGesture() {
        guard let onGesture else { return }
        for type in Self.gestures {
            _ = JSObject.global.document.removeEventListener(type, onGesture, true)
        }
        self.onGesture = nil
    }

    // MARK: Playing

    private func connect(to context: JSObject) {
        guard playing, node == nil else { return }
        let processorOptions = JSObject()
        processorOptions.channels = .number(Double(channels))
        let options = JSObject()
        options.numberOfInputs = 0
        options.numberOfOutputs = 1
        options.outputChannelCount = [channels].jsValue
        options.processorOptions = processorOptions.jsValue
        let node = JSObject.global.AudioWorkletNode.function!.new(context, "nucleant-audio-stream", options)
        let onMessage = JSClosure { [weak self] arguments in
            guard let self, let taken = arguments.first?.data.number else { return .undefined }
            queued -= Int(taken)
            fill()
            return .undefined
        }
        node.port.onmessage = onMessage.jsValue
        _ = node.connect!(context.destination)
        self.node = node
        self.onMessage = onMessage
        queued = 0
        fill()
    }

    /// Tops what is on its way up to `lead` seconds.
    private func fill() {
        let target = Int((sampleRate * Self.lead).rounded())
        while let node, queued < target {
            let frames = min(Self.capacity, target - queued)
            let interleaved = UnsafeMutableBufferPointer(rebasing: buffer[0..<(frames * channels)])
            var span = interleaved.mutableSpan
            renderer.render(into: &span, channels: channels, sampleRate: sampleRate)
            let chunk = JSTypedArray<Float>(buffer: UnsafeBufferPointer(interleaved))
            _ = node.port.postMessage(chunk, [chunk.jsObject.buffer])
            queued += frames
        }
    }

    // MARK: Settings

    private static var preferredRate: Double { 48_000 }

    /// What a busy page can fall behind by before it clicks.
    private static var lead: Double { 0.06 }

    /// The most frames rendered at once.
    private static var capacity: Int { 4096 }

    private static var gestures: [String] { ["pointerdown", "touchend", "keydown"] }

    /// The worklet's processor: plays the chunks sent to it, interleaved, and
    /// reports every 512 frames played — at once when it has run dry (the
    /// page fell behind, a click), so the output catches up.
    private static var worklet: String {
        #"""
        class NucleantAudioStream extends AudioWorkletProcessor {
          constructor(options) {
            super();
            this.channels = options.processorOptions.channels;
            this.chunks = [];
            this.offset = 0;
            this.taken = 0;
            this.playing = true;
            this.port.onmessage = (event) => {
              if (event.data === 'stop') this.playing = false;
              else this.chunks.push(event.data);
            };
          }

          process(inputs, outputs) {
            if (!this.playing) return false;
            const output = outputs[0];
            const frames = output[0].length;
            const channels = this.channels;
            let done = 0;
            while (done < frames && this.chunks.length) {
              const chunk = this.chunks[0];
              const count = Math.min(chunk.length / channels - this.offset, frames - done);
              for (let channel = 0; channel < output.length; channel++) {
                const out = output[channel];
                const from = Math.min(channel, channels - 1);
                for (let frame = 0; frame < count; frame++) out[done + frame] = chunk[(this.offset + frame) * channels + from];
              }
              done += count;
              this.offset += count;
              if (this.offset * channels >= chunk.length) {
                this.chunks.shift();
                this.offset = 0;
              }
            }
            for (const out of output) out.fill(0, done);
            this.taken += done;
            if (this.taken >= 512 || (done < frames && this.taken > 0)) {
              this.port.postMessage(this.taken);
              this.taken = 0;
            }
            return true;
          }
        }
        registerProcessor('nucleant-audio-stream', NucleantAudioStream);
        """#
    }
}
