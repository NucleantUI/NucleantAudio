//
//  AppleAudio.swift
//  NucleantAudio
//
//  What NucleantAudio plays and loads through on Apple platforms: AVFoundation
//  for both. The output is per OS (`AVFoundationOutput+MacOS.swift`,
//  `AVFoundationOutput+iOS.swift`, one class under one name), the decoder the
//  same everywhere.
//

import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = AVFoundationOutput<Renderer>

public typealias DefaultAudioDecoder = AVFoundationDecoder
