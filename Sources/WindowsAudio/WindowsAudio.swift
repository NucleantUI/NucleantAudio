//
//  WindowsAudio.swift
//  NucleantAudio
//
//  Not yet: Windows' output is WASAPI (an IAudioClient in shared mode, fed
//  from its own thread) and its decoder Media Foundation (an IMFSourceReader
//  asked for float PCM), each a backend of its own to write. Until then both
//  compile and fail visibly — the output's `init` and the decoder throw
//  `unsupportedPlatform` — so the rest of the package builds and runs on
//  Windows.
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
