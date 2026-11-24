//
//  NucleantAudioTests.swift
//  NucleantAudioTests
//
//  Files written here and read back through each platform's decoder, and a
//  player run against the real default output — playing silence, so a run
//  makes no sound. With no output to open (a machine without audio) the
//  player's tests have nothing to check, and pass. And processors on their
//  own, rendering into a span with no output involved.
//

import Foundation
import NucleantAudio
import Testing

@Suite(.serialized)
struct NucleantAudioTests {

    // MARK: Loading

    @Test func aWAVFileComesBackAsItsSamples() throws {
        // 16-bit stereo at 22.05 kHz: a ramp up on the left, down on the right.
        let frames = 1000
        var samples: [Int16] = []
        for frame in 0..<frames {
            samples.append(Int16(frame * 32))
            samples.append(Int16(-frame * 32))
        }
        let url = try write(wav: pcm16(samples), format: 1, channels: 2, sampleRate: 22_050, bits: 16)
        defer { try? FileManager.default.removeItem(at: url) }

        let clip = try AudioFileLoader().load(contentsOf: url)
        #expect(clip.sampleRate == 22_050)
        #expect(clip.channels.count == 2)
        #expect(clip.frameCount == frames)
        for frame in [0, 1, 500, 999] {
            #expect(abs(clip.channels[0][frame] - Float(frame * 32) / 32_768) < 1e-4)
            #expect(abs(clip.channels[1][frame] + Float(frame * 32) / 32_768) < 1e-4)
        }
    }

    @Test func aFloatWAVFileComesBackExactly() throws {
        let samples: [Float] = (0..<480).map { sin(Float($0) / 480 * 2 * .pi) * 0.5 }
        var bytes: [UInt8] = []
        for sample in samples { withUnsafeBytes(of: sample.bitPattern.littleEndian) { bytes += $0 } }
        let url = try write(wav: bytes, format: 3, channels: 1, sampleRate: 48_000, bits: 32)
        defer { try? FileManager.default.removeItem(at: url) }

        let clip = try AudioFileLoader().load(contentsOf: url)
        #expect(clip.sampleRate == 48_000)
        #expect(clip.channels.count == 1)
        #expect(clip.channels[0] == samples)
    }

    @Test func aFileThatIsNotAudioIsNotLoaded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nucleant-not-audio-\(UUID()).wav")
        try Data("this is not a sound".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try AudioFileLoader().load(contentsOf: url) }
        #expect(throws: (any Error).self) {
            try AudioFileLoader().load(contentsOf: url.appendingPathExtension("missing"))
        }
    }

    // MARK: Playing

    @MainActor
    @Test func thePlayerIsAskedForFramesAtItsRateWhileItRuns() async throws {
        guard let player = openPlayer(Counter(), channels: 2) else { return }
        #expect(player.sampleRate > 0)
        try player.start()
        #expect(player.isRunning)
        try await Task.sleep(for: .milliseconds(500))
        player.stop()
        #expect(!player.isRunning)

        let (frames, channels, rate) = player.withProcessor { ($0.frames, $0.channels, $0.sampleRate) }
        #expect(channels == 2)
        #expect(rate == player.sampleRate)
        // Half a second's worth, give or take what the device buffers.
        #expect(Double(frames) > player.sampleRate * 0.3)
        #expect(Double(frames) < player.sampleRate * 0.8)

        // Stopped, it is asked for nothing more…
        try await Task.sleep(for: .milliseconds(150))
        #expect(player.withProcessor { $0.frames } == frames)

        // …and started again, it goes on.
        try player.start()
        try await Task.sleep(for: .milliseconds(200))
        player.stop()
        #expect(player.withProcessor { $0.frames } > frames)
    }

    @MainActor
    @Test func aMonoPlayerRendersOneChannel() async throws {
        guard let player = openPlayer(Counter(), channels: 1) else { return }
        try player.start()
        try await Task.sleep(for: .milliseconds(100))
        player.stop()
        #expect(player.channels == 1)
        #expect(player.withProcessor { $0.channels } == 1)
        #expect(player.withProcessor { $0.frames } > 0)
    }

    @MainActor
    @Test func aLoadedClipPlaysToItsEndAtTheOutputsPace() async throws {
        // A quarter of a second at 44.1 kHz, which the output resamples —
        // silent, like the rest of these runs.
        let url = try write(wav: pcm16([Int16](repeating: 0, count: 11_025)), format: 1, channels: 1, sampleRate: 44_100, bits: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        let clip = try AudioFileLoader().load(contentsOf: url)
        #expect(clip.duration == 0.25)

        guard let player = openPlayer(ClipPlayback(), channels: 2) else { return }
        try player.start()
        defer { player.stop() }
        let started = ContinuousClock.now
        player.withProcessor { $0.play(clip) }
        #expect(player.withProcessor { $0.isPlaying })
        while player.withProcessor({ $0.isPlaying }), ContinuousClock.now - started < .seconds(2) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let elapsed = ContinuousClock.now - started
        #expect(!player.withProcessor { $0.isPlaying })
        #expect(player.withProcessor { $0.currentTime } == nil)
        // As long as the clip, less what the device takes ahead of time.
        #expect(elapsed > .milliseconds(150))
        #expect(elapsed < .milliseconds(600))
    }

    // MARK: Rendering

    // A processor on its own, no output involved: what it writes into the
    // span it is lent.

    @Test func nothingToPlayIsSilence() {
        var playback = ClipPlayback()
        #expect(render(&playback, frames: 4, channels: 2, sampleRate: 48_000) == [Float](repeating: 0, count: 8))
        #expect(!playback.isPlaying)
    }

    @Test func aClipIsResampledToTheOutputsRateAndEndsInSilence() {
        // 24 kHz into 48 kHz: half a clip frame per output frame, the
        // in-between ones interpolated, the last held until the clip ends.
        var playback = ClipPlayback()
        playback.play(AudioClip(sampleRate: 24_000, mono: [0, 1, 2, 3]))
        let first = render(&playback, frames: 8, channels: 2, sampleRate: 48_000)
        let expected: [Float] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3]
        #expect(first == expected.flatMap { [$0, $0] })
        #expect(!playback.isPlaying)
        #expect(render(&playback, frames: 4, channels: 2, sampleRate: 48_000) == [Float](repeating: 0, count: 8))
    }

    @Test func aStereoClipPlaysEachChannelAndRepeatsItsLastPastIt() {
        var playback = ClipPlayback()
        playback.play(AudioClip(sampleRate: 48_000, channels: [[1, 2], [-1, -2]]))
        #expect(playback.currentTime == 0)
        let samples = render(&playback, frames: 2, channels: 3, sampleRate: 48_000)
        #expect(samples == [1, -1, -1, 2, -2, -2])
    }

    @Test func playingAgainRestartsWithTheNewClip() {
        var playback = ClipPlayback()
        playback.play(AudioClip(sampleRate: 48_000, mono: [1, 1, 1, 1]))
        _ = render(&playback, frames: 2, channels: 1, sampleRate: 48_000)
        #expect(playback.currentTime == 2.0 / 48_000)
        playback.play(AudioClip(sampleRate: 48_000, mono: [5, 6]))
        #expect(render(&playback, frames: 3, channels: 1, sampleRate: 48_000) == [5, 6, 0])
        playback.stop()
        #expect(!playback.isPlaying)
        #expect(playback.currentTime == nil)
    }

    // MARK: Helpers

    /// What `processor` writes over `frames` frames of `channels`, into a
    /// buffer that starts out as NaN so nothing left unwritten passes.
    ///
    /// A `ContiguousArray`, whose `mutableSpan` back-deploys to every OS the
    /// package supports. `Array`'s is macOS/iOS 26 and up: on Apple
    /// platforms an array may be a bridged `NSArray`, and making that
    /// contiguous for a span needs the newer runtime.
    private func render<Processor: AudioProcessor>(
        _ processor: inout Processor,
        frames: Int,
        channels: Int,
        sampleRate: Double
    ) -> [Float] {
        var samples = ContiguousArray<Float>(repeating: .nan, count: frames * channels)
        var span = samples.mutableSpan
        processor.process(into: &span, channels: channels, sampleRate: sampleRate)
        return Array(samples)
    }

    /// Silence, counting what it is asked for.
    struct Counter: AudioProcessor {
        var frames = 0
        var channels = 0
        var sampleRate = 0.0

        mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
            buffer.update(repeating: 0)
            frames += buffer.count / channels
            self.channels = channels
            self.sampleRate = sampleRate
        }
    }

    @MainActor
    private func openPlayer<Processor: AudioProcessor>(_ processor: Processor, channels: Int) -> AudioPlayer<Processor>? {
        do {
            return try AudioPlayer(processor, channels: channels)
        } catch {
            print("No audio output to test against: \(error)")
            return nil
        }
    }

    private func pcm16(_ samples: [Int16]) -> [UInt8] {
        samples.flatMap { sample in withUnsafeBytes(of: sample.littleEndian) { Array($0) } }
    }

    /// A RIFF WAVE file of `data`, in the temporary directory.
    private func write(wav data: [UInt8], format: UInt16, channels: UInt16, sampleRate: UInt32, bits: UInt16) throws -> URL {
        var bytes: [UInt8] = []
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { bytes += $0 } }
        let blockAlign = channels * bits / 8
        bytes += Array("RIFF".utf8); append(UInt32(36 + data.count)); bytes += Array("WAVE".utf8)
        bytes += Array("fmt ".utf8); append(UInt32(16)); append(format); append(channels)
        append(sampleRate); append(sampleRate * UInt32(blockAlign)); append(blockAlign); append(bits)
        bytes += Array("data".utf8); append(UInt32(data.count)); bytes += data
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nucleant-audio-\(UUID()).wav")
        try Data(bytes).write(to: url)
        return url
    }
}
