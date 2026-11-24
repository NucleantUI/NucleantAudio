//
//  NucleantAudio.swift
//  NucleantAudio
//
//  The one place in NucleantAudio that knows there is more than one
//  platform. A build has exactly one platform target (Package.swift picks it
//  by platform), each declares the same `DefaultAudioOutput` and
//  `DefaultAudioDecoder`, and this file imports whichever target it is. The
//  rest of the module uses them through the names below and the protocols in
//  AudioProtocols, and never says which platform it is on.
//
//  By `os`, the same conditions as the dependencies in Package.swift, rather
//  than `canImport`: a module built for another reason (an editor's index
//  build compiles every target) would otherwise be picked up.
//

@_exported import AudioProtocols

#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
internal import AppleAudio
#elseif os(Linux)
internal import LinuxAudio
#elseif os(Android)
internal import AndroidAudio
#elseif os(Windows)
internal import WindowsAudio
#elseif os(WASI)
internal import WasmAudio
#else
#error("NucleantAudio has no platform target for this platform: add one, and its condition in Package.swift")
#endif

/// The output `AudioPlayer` plays through.
typealias PlatformAudioOutput<Renderer: AudioRenderer> = DefaultAudioOutput<Renderer>

/// The decoder `AudioFileLoader` reads with.
typealias PlatformAudioDecoder = DefaultAudioDecoder
