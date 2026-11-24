//
//  WasmAudio.swift
//  NucleantAudio
//
//  What NucleantAudio plays and loads through in a browser: Web Audio for
//  both, through JavaScriptKit — the output an AudioWorklet
//  (WebAudioOutput.swift), the decoder `decodeAudioData`, waited for under
//  JSPI (WebAudioDecoder.swift).
//

import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = WebAudioOutput<Renderer>

public typealias DefaultAudioDecoder = WebAudioDecoder
