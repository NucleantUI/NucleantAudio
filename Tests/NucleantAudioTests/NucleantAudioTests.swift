//
//  NucleantAudioTests.swift
//  NucleantAudioTests
//
//  Files read back through each platform's decoder — fixtures, not files
//  the tests write, as a browser's file system is read-only:
//
//    stereo-ramp-22050.wav   16-bit stereo at 22.05 kHz, 1000 frames: left
//                            frame × 32, right −frame × 32
//    stereo-ramp-22050.flac  the same, as FLAC
//    float-mono-48000.wav    32-bit float mono at 48 kHz, 480 frames:
//                            (frame − 240) / 512, each exact in a Float
//    silence-44100.wav       16-bit mono at 44.1 kHz, a quarter of a second
//    not-audio.wav           "this is not a sound"
//
//  And a player run against the real default output — playing silence, so a
//  run makes no sound. With no output to open (a machine without audio) the
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
        try expectStereoRamp(AudioFileLoader().load(contentsOf: fixture("stereo-ramp-22050.wav")))
    }

    @Test func aFLACFileComesBackAsItsSamplesAtItsOwnRate() throws {
        try expectStereoRamp(AudioFileLoader().load(contentsOf: fixture("stereo-ramp-22050.flac")))
    }

    @Test func aFloatWAVFileComesBackExactly() throws {
        let clip = try AudioFileLoader().load(contentsOf: fixture("float-mono-48000.wav"))
        #expect(clip.sampleRate == 48_000)
        #expect(clip.channels.count == 1)
        #expect(clip.channels[0] == (0..<480).map { Float($0 - 240) / 512 })
    }

    @Test func aFileThatIsNotAudioIsNotLoaded() throws {
        let url = try fixture("not-audio.wav")
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
        let clip = try AudioFileLoader().load(contentsOf: fixture("silence-44100.wav"))
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

    /// A file from Fixtures (see the top of this file). Put together from
    /// the bundle's resource directory rather than looked up: on WASI,
    /// Foundation's `url(forResource:withExtension:subdirectory:)` returns
    /// the file's name less its last character.
    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    /// stereo-ramp-22050's samples, at its own rate.
    private func expectStereoRamp(_ clip: AudioClip) {
        #expect(clip.sampleRate == 22_050)
        #expect(clip.channels.count == 2)
        #expect(clip.frameCount == 1000)
        guard clip.channels.count == 2, clip.frameCount == 1000 else { return }
        for frame in [0, 1, 500, 999] {
            #expect(abs(clip.channels[0][frame] - Float(frame * 32) / 32_768) < 1e-4)
            #expect(abs(clip.channels[1][frame] + Float(frame * 32) / 32_768) < 1e-4)
        }
    }
}
