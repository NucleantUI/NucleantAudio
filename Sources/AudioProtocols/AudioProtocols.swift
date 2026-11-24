//
//  AudioProtocols.swift
//  NucleantAudio
//
//  What each platform target (AppleAudio, LinuxAudio, AndroidAudio,
//  WindowsAudio, WasmAudio) provides, so NucleantAudio can drive it without
//  knowing which one it has. A platform target conforms its own types to
//  these, then names the ones NucleantAudio is to use:
//
//      public typealias DefaultAudioOutput<Renderer: AudioRenderer> = ALSAOutput<Renderer>
//      public typealias DefaultAudioDecoder = SndFileDecoder
//
//  Every platform target declares those same two names, and a build has only
//  one of the targets.
//

import Foundation

/// What an `AudioOutput` asks for its samples, on the audio thread.
///
/// NucleantAudio's `AudioPlayer` hands the output its processor wrapped in
/// one, with the lock that keeps the main actor's changes between buffers.
public protocol AudioRenderer: AnyObject, Sendable {
    /// Fill `buffer` — `buffer.count / channels` frames, `channels` samples
    /// each, interleaved — for an output running at `sampleRate`.
    func render(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double)
}

/// A platform's default output device, playing what a renderer makes.
///
/// The device stays open from `init` to the output's end; between `start`
/// and `stop` it calls `renderer` from its own thread, a buffer at a time.
public protocol AudioOutput: AnyObject {
    associatedtype Renderer: AudioRenderer

    /// Opens the default output with `channels` channels, at a rate of the
    /// output's choosing — the device's own where it says. Nothing sounds
    /// until `start()`.
    init(channels: Int, renderer: Renderer) throws

    /// The rate `renderer` is asked to render at.
    var sampleRate: Double { get }

    func start() throws

    /// Silent at once: what was rendered and not yet played goes.
    func stop()
}

/// A platform's decoder: an audio file read whole into memory, as Float
/// samples at the file's own rate.
public protocol AudioDecoder: Sendable {
    init()

    func decode(contentsOf url: URL) throws -> AudioClip
}
