//
//  WebAudioDecoder.swift
//  NucleantAudio
//
//  The browser's own decoder, `decodeAudioData`, through JavaScriptKit: it
//  reads whatever the browser does (WAV, AIFF, MP3, AAC/M4A, FLAC, Ogg Vorbis
//  and Opus in Chrome), out as Float samples. It only answers through a
//  Promise, and `decode` returns the clip, so it waits for that Promise under
//  JSPI — the call into the module suspended meanwhile — with the page's
//  `await_promise` (NucleantApplication's Web/nucleant-app.js). Without JSPI
//  it throws `decoderUnavailable`. Loading in the browser therefore has to be
//  reached from a call the page made into the module (an event, a frame, the
//  main queue, a task), not from inside a JavaScript callback.
//
//  `decodeAudioData` converts to the rate of the context it decodes for and
//  never says the file's own, so the context is made at the rate the file
//  states where its container states it in a fixed place — a WAV's fmt
//  chunk, a FLAC's STREAMINFO — which gives those files' samples unchanged.
//  Any other comes at 48 kHz, the output's rate.
//

import Foundation
import AudioProtocols
@_spi(JSObject_id) import JavaScriptKit

public struct WebAudioDecoder: AudioDecoder {
    public init() {}

    public func decode(contentsOf url: URL) throws -> AudioClip {
        guard let OfflineAudioContext = JSObject.global.OfflineAudioContext.function else {
            throw AudioFileError.decoderUnavailable("this browser has no Web Audio (OfflineAudioContext)")
        }
        guard let bytes = try? [UInt8](Data(contentsOf: url)) else {
            throw AudioFileError.unreadable(url)
        }
        let rate = Self.statedSampleRate(of: bytes) ?? Self.fallbackRate
        let context = OfflineAudioContext.new(1, 1, rate)
        let file = bytes.withUnsafeBufferPointer { JSTypedArray<UInt8>(buffer: $0) }
        guard let decoding = context.decodeAudioData!(file.jsObject.buffer).object else {
            throw AudioFileError.unreadable(url)
        }
        let (decoded, buffer) = try Self.settle(decoding)
        let channelCount = Int(buffer.numberOfChannels.number ?? 0)
        guard decoded, channelCount > 0, (buffer.length.number ?? 0) > 0 else {
            throw AudioFileError.unreadable(url)
        }
        let channels = (0..<channelCount).map { channel in
            JSTypedArray<Float>(unsafelyWrapping: buffer.getChannelData!(channel).object!).withUnsafeBytes { Array($0) }
        }
        return AudioClip(sampleRate: buffer.sampleRate.number ?? rate, channels: channels)
    }

    private static var fallbackRate: Double { 48_000 }

    /// Waits for `promise` to settle: whether it was fulfilled, and what it
    /// settled to.
    private static func settle(_ promise: JSObject) throws -> (fulfilled: Bool, value: JSObject) {
        var settled: UInt32 = 0
        let status = nucleantAwaitPromise(promise.id, &settled)
        guard status >= 0 else {
            throw AudioFileError.decoderUnavailable(
                "the browser's decoder only answers through a Promise, and waiting for it takes JSPI, which this page runs without"
            )
        }
        return (status == 1, JSObject(id: settled))
    }

    /// The rate a WAV's fmt chunk or a FLAC's STREAMINFO states; nil for any
    /// other file.
    static func statedSampleRate(of bytes: [UInt8]) -> Double? {
        func uint32(at offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
        }
        func tag(at offset: Int) -> String? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
        }
        if tag(at: 0) == "RIFF", tag(at: 8) == "WAVE" {
            // Chunks from 12: a tag, a little-endian size, the data padded to
            // an even length. The rate is fmt's second field.
            var offset = 12
            while let name = tag(at: offset), let size = uint32(at: offset + 4) {
                if name == "fmt " {
                    return uint32(at: offset + 12).flatMap { $0 > 0 ? Double($0) : nil }
                }
                offset += 8 + Int(size) + Int(size % 2)
            }
            return nil
        }
        // STREAMINFO is always the first block: after "fLaC" and its 4-byte
        // header, 10 bytes of block and frame sizes, then the rate's 20 bits.
        if tag(at: 0) == "fLaC", bytes.count >= 21, bytes[4] & 0x7F == 0 {
            let rate = UInt32(bytes[18]) << 12 | UInt32(bytes[19]) << 4 | UInt32(bytes[20]) >> 4
            return rate > 0 ? Double(rate) : nil
        }
        return nil
    }
}

/// The page's `await_promise`: waits for the promise JavaScriptKit holds as
/// `promise` (a JavaScriptObjectRef, which is a UInt32) to settle, writes the reference of what it settled to into
/// `result`, and returns 1 fulfilled, 0 rejected — or -1 at once, without
/// JSPI.
@_extern(wasm, module: "nucleant_javascriptkit", name: "await_promise")
private func nucleantAwaitPromise(_ promise: UInt32, _ result: UnsafeMutablePointer<UInt32>) -> Int32
