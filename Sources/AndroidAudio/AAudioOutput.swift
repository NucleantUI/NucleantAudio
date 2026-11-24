//
//  AAudioOutput.swift
//  NucleantAudio
//
//  AAudio's default output, in shared, low-latency mode: a Float stream that
//  calls back on AAudio's own high-priority thread for each buffer, where the
//  renderer fills it in place. The rate is the device's, as AAudio opens it.
//
//  A stream AAudio disconnects — the device it plays to went, headphones
//  unplugged, a route change — cannot play again. It is closed and a new one
//  opened on the new default, from a thread of its own (AAudio forbids
//  closing a stream from its callbacks), playing again if it was.
//

import Foundation
import AudioProtocols
import CAndroidAudio

public final class AAudioOutput<Renderer: AudioRenderer>: AudioOutput {
    private let playback: AAudioPlayback

    public init(channels: Int, renderer: Renderer) throws {
        playback = try AAudioPlayback(channels: channels) { buffer, channels, sampleRate in
            renderer.render(into: &buffer, channels: channels, sampleRate: sampleRate)
        }
    }

    deinit {
        playback.close()
    }

    /// The rate the stream was opened at — the device's. A stream reopened
    /// after a route change may run at another; the renderer is told each
    /// time.
    public var sampleRate: Double { playback.sampleRate }

    public func start() throws {
        try playback.start()
    }

    public func stop() {
        playback.stop()
    }
}

/// The open stream, and what renders into it: what AAudio's callbacks are
/// given (its address is their context), so it is not generic — the
/// renderer is kept as a closure.
final class AAudioPlayback: @unchecked Sendable {
    typealias Render = (inout MutableSpan<Float>, Int, Double) -> Void

    let channels: Int
    private let renderer: Render
    /// Guards the stream against `start`, `stop`, `close` and a reopen
    /// meeting. The callbacks never take it.
    private let lock = NSLock()
    private var stream: OpaquePointer?
    private var playing = false
    private var closed = false
    /// The open stream's rate. Written only while no stream is calling back,
    /// so the render callback reads it without the lock.
    private var rate: Double = 0

    init(channels: Int, renderer: @escaping Render) throws {
        self.channels = channels
        self.renderer = renderer
        try lock.withLock { try open() }
    }

    var sampleRate: Double {
        lock.withLock { rate }
    }

    func start() throws {
        try lock.withLock {
            guard let stream, !playing else { return }
            let result = AAudioStream_requestStart(stream)
            guard result == AAUDIO_OK else {
                throw AudioPlayerError.outputUnavailable("AAudio could not start the output: \(Self.describe(result))")
            }
            playing = true
        }
    }

    /// Paused and flushed, rather than stopped, which would play out what is
    /// queued: a stopped player is silent at once.
    func stop() {
        lock.withLock {
            guard let stream, playing else { return }
            _ = AAudioStream_requestPause(stream)
            _ = AAudioStream_requestFlush(stream)
            playing = false
        }
    }

    func close() {
        lock.withLock {
            closed = true
            if let stream { AAudioStream_close(stream) }
            stream = nil
            playing = false
        }
    }

    /// `frames` frames into `audioData`, on AAudio's thread.
    fileprivate func render(into audioData: UnsafeMutableRawPointer, frames: Int) {
        let buffer = UnsafeMutableBufferPointer(start: audioData.assumingMemoryBound(to: Float.self), count: frames * channels)
        var span = buffer.mutableSpan
        renderer(&span, channels, rate)
    }

    /// The stream was disconnected: replaced, from a thread of its own.
    fileprivate func disconnected() {
        let thread = Thread { [self] in reopen() }
        thread.name = "NucleantAudio reopen"
        thread.start()
    }

    private func reopen() {
        lock.withLock {
            guard !closed else { return }
            if let stream { AAudioStream_close(stream) }
            stream = nil
            do {
                try open()
                if playing, let stream {
                    let result = AAudioStream_requestStart(stream)
                    if result != AAUDIO_OK { throw AudioPlayerError.outputUnavailable(Self.describe(result)) }
                }
            } catch {
                playing = false
                FileHandle.standardError.write(Data("NucleantAudio: the output stopped: \(error)\n".utf8))
            }
        }
    }

    /// A Float stream of `channels` on the default output; under the lock.
    private func open() throws {
        var builder: OpaquePointer?
        var result = AAudio_createStreamBuilder(&builder)
        guard result == AAUDIO_OK, let builder else {
            throw AudioPlayerError.outputUnavailable("AAudio could not make a stream: \(Self.describe(result))")
        }
        defer { AAudioStreamBuilder_delete(builder) }
        AAudioStreamBuilder_setDirection(builder, aaudio_direction_t(AAUDIO_DIRECTION_OUTPUT))
        AAudioStreamBuilder_setFormat(builder, aaudio_format_t(AAUDIO_FORMAT_PCM_FLOAT))
        AAudioStreamBuilder_setChannelCount(builder, Int32(channels))
        AAudioStreamBuilder_setSharingMode(builder, aaudio_sharing_mode_t(AAUDIO_SHARING_MODE_SHARED))
        AAudioStreamBuilder_setPerformanceMode(builder, aaudio_performance_mode_t(AAUDIO_PERFORMANCE_MODE_LOW_LATENCY))
        AAudioStreamBuilder_setUsage(builder, aaudio_usage_t(AAUDIO_USAGE_MEDIA))
        let context = Unmanaged.passUnretained(self).toOpaque()
        AAudioStreamBuilder_setDataCallback(builder, { _, context, audioData, frames in
            guard let context else { return aaudio_data_callback_result_t(AAUDIO_CALLBACK_RESULT_STOP) }
            Unmanaged<AAudioPlayback>.fromOpaque(context).takeUnretainedValue().render(into: audioData, frames: Int(frames))
            return aaudio_data_callback_result_t(AAUDIO_CALLBACK_RESULT_CONTINUE)
        }, context)
        AAudioStreamBuilder_setErrorCallback(builder, { _, context, error in
            guard error == aaudio_result_t(AAUDIO_ERROR_DISCONNECTED), let context else { return }
            Unmanaged<AAudioPlayback>.fromOpaque(context).takeUnretainedValue().disconnected()
        }, context)

        var opened: OpaquePointer?
        result = AAudioStreamBuilder_openStream(builder, &opened)
        guard result == AAUDIO_OK, let opened else {
            throw AudioPlayerError.outputUnavailable("AAudio could not open the default output: \(Self.describe(result))")
        }
        let rate = Double(AAudioStream_getSampleRate(opened))
        guard AAudioStream_getFormat(opened) == aaudio_format_t(AAUDIO_FORMAT_PCM_FLOAT),
              AAudioStream_getChannelCount(opened) == Int32(channels)
        else {
            AAudioStream_close(opened)
            throw AudioPlayerError.unsupportedFormat(channels: channels, sampleRate: rate)
        }
        self.rate = rate
        stream = opened
    }

    private static func describe(_ result: aaudio_result_t) -> String {
        String(cString: AAudio_convertResultToText(result))
    }
}
