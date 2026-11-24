//
//  AudioPlayer.swift
//  NucleantAudio
//
//  The part every platform shares: the processor and the lock around it.
//  What actually opens the output device and calls `process` from the
//  audio thread is the platform target's `DefaultAudioOutput`.
//

import Foundation
import AudioProtocols

/// Plays what an `AudioProcessor` makes, through the default output device.
///
/// The processor is owned here and runs on the audio thread; the main actor
/// reaches it only through `withProcessor`, under the same lock `process`
/// runs under — so settings change between buffers, never halfway through
/// one.
@MainActor
public final class AudioPlayer<Processor: AudioProcessor> {
    private let box: ProcessorBox<Processor>
    private let output: PlatformAudioOutput<ProcessorBox<Processor>>
    public let channels: Int
    public private(set) var isRunning = false

    /// Opens the default output with `channels` channels, at the device's
    /// own sample rate. Nothing sounds until `start()`.
    public init(_ processor: Processor, channels: Int = 1) throws {
        let box = ProcessorBox(processor)
        self.box = box
        self.channels = max(1, channels)
        self.output = try PlatformAudioOutput(channels: max(1, channels), renderer: box)
    }

    /// The rate `process` is asked to render at.
    public var sampleRate: Double { output.sampleRate }

    public func start() throws {
        guard !isRunning else { return }
        try output.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        output.stop()
        isRunning = false
    }

    /// Read or change the processor, between two of its buffers.
    public func withProcessor<Result>(_ body: (inout Processor) throws -> Result) rethrows -> Result {
        try box.withProcessor(body)
    }
}

/// The processor and its lock, shared by the player (main actor) and the
/// output (audio thread). Every access goes through the lock, which is what
/// makes the `@unchecked Sendable` true.
final class ProcessorBox<Processor: AudioProcessor>: AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var processor: Processor

    init(_ processor: Processor) {
        self.processor = processor
    }

    func render(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        processor.process(into: &buffer, channels: channels, sampleRate: sampleRate)
    }

    func withProcessor<Result>(_ body: (inout Processor) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&processor)
    }
}
