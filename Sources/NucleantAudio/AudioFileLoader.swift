//
//  AudioFileLoader.swift
//  NucleantAudio
//
//  The part every platform shares. The decoding itself is the platform
//  target's `DefaultAudioDecoder`.
//

import Foundation
import AudioProtocols

/// Loads an audio file into memory as an `AudioClip`, decoded to Float
/// samples at the file's own sample rate.
public struct AudioFileLoader: Sendable {
    public init() {}

    public func load(contentsOf url: URL) throws -> AudioClip {
        try PlatformAudioDecoder().decode(contentsOf: url)
    }
}
