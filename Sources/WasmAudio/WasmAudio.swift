//
//  WasmAudio.swift
//  NucleantAudio
//
//  What NucleantAudio plays and loads through in a browser: Web Audio for the
//  output (WebAudioOutput.swift), through JavaScriptKit.
//
//  No decoder yet. The browser's own, `decodeAudioData`, only answers later
//  (a Promise), while `AudioDecoder.decode` returns the clip; waiting on it
//  takes JSPI, which only some browsers have. Until then loading compiles and
//  fails visibly — it throws `unsupportedPlatform` — so the rest of the
//  package builds and runs in the browser.
//

import Foundation
import AudioProtocols

public typealias DefaultAudioOutput<Renderer: AudioRenderer> = WebAudioOutput<Renderer>

public typealias DefaultAudioDecoder = UnsupportedDecoder

public struct UnsupportedDecoder: AudioDecoder {
    public init() {}

    public func decode(contentsOf url: URL) throws -> AudioClip {
        throw AudioFileError.unsupportedPlatform
    }
}
