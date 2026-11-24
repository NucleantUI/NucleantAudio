//
//  AndroidAudio.swift
//  NucleantAudio
//
//  Not yet: Android's output is AAudio (an AAudioStream in shared,
//  low-latency mode, calling back on its own thread) and its decoder the
//  NDK's media codecs (AMediaExtractor into AMediaCodec, out as PCM), each a
//  backend of its own to write. Until then both compile and fail visibly —
//  the output's `init` and the decoder throw `unsupportedPlatform` — so the
//  rest of the package builds and runs on Android.
//

import Foundation
import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = UnsupportedOutput<Renderer>

public typealias DefaultAudioDecoder = UnsupportedDecoder

public final class UnsupportedOutput<Renderer: AudioRenderer>: AudioOutput {
    public var sampleRate: Double { 0 }

    public init(channels: Int, renderer: Renderer) throws {
        throw AudioPlayerError.unsupportedPlatform
    }

    public func start() throws {
        throw AudioPlayerError.unsupportedPlatform
    }

    public func stop() {}
}

public struct UnsupportedDecoder: AudioDecoder {
    public init() {}

    public func decode(contentsOf url: URL) throws -> AudioClip {
        throw AudioFileError.unsupportedPlatform
    }
}
