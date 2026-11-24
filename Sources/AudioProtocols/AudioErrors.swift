//
//  AudioErrors.swift
//  NucleantAudio
//
//  What an `AudioOutput` and an `AudioDecoder` throw, on every platform.
//

import Foundation

public enum AudioPlayerError: Error {
    /// The output could not take `channels` channels at `sampleRate`.
    case unsupportedFormat(channels: Int, sampleRate: Double)
    /// The default output could not be opened or started — there is none,
    /// or the system's audio library is missing. Says why, in the system's
    /// words.
    case outputUnavailable(String)
    /// This platform has no audio output backend yet.
    case unsupportedPlatform
}

public enum AudioFileError: Error {
    /// The file could not be opened or decoded.
    case unreadable(URL)
    /// The system's decoder could not be loaded, so no file can be read —
    /// libsndfile missing on Linux. Says which.
    case decoderUnavailable(String)
    /// This platform has no audio decoder yet.
    case unsupportedPlatform
}
