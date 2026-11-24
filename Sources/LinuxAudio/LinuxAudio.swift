//
//  LinuxAudio.swift
//  NucleantAudio
//
//  What NucleantAudio plays and loads through on Linux: ALSA's default PCM
//  for the output, libsndfile for the decoder. Both are opened at run time
//  rather than linked, so building needs neither library's headers.
//

import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = ALSAOutput<Renderer>

public typealias DefaultAudioDecoder = SndFileDecoder
