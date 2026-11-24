//
//  AndroidAudio.swift
//  NucleantAudio
//
//  What NucleantAudio plays and loads through on Android: AAudio for the
//  output, the NDK's media extractor and codecs for the decoder, both
//  reached through the NDK headers in the Swift Android SDK (CAndroidAudio).
//

import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = AAudioOutput<Renderer>

public typealias DefaultAudioDecoder = MediaCodecDecoder
