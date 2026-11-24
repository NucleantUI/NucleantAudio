//
//  MediaCodecDecoder.swift
//  NucleantAudio
//
//  The NDK's media extractor and codecs: the file's first audio track,
//  through the decoder Android has for it — WAV, FLAC, MP3, AAC/M4A, Ogg
//  Vorbis and Opus on every device — out as PCM at the file's own rate, in
//  whatever encoding the decoder's output format states (16-bit unless it
//  says otherwise), converted to Float here. Float is not asked for: a
//  decoder that cannot give it — WAV's raw passthrough, FLAC's on the
//  emulator — still repeats the request in its output format, and the
//  16-bit samples it does give would then be read as Floats.
//

import Foundation
import AudioProtocols
import CAndroidAudio

public struct MediaCodecDecoder: AudioDecoder {
    public init() {}

    public func decode(contentsOf url: URL) throws -> AudioClip {
        guard let file = try? FileHandle(forReadingFrom: url), let length = try? file.seekToEnd() else {
            throw AudioFileError.unreadable(url)
        }
        defer { try? file.close() }
        guard let extractor = AMediaExtractor_new() else {
            throw AudioFileError.decoderUnavailable("the NDK's media extractor could not be made")
        }
        defer { AMediaExtractor_delete(extractor) }
        guard AMediaExtractor_setDataSourceFd(extractor, file.fileDescriptor, 0, off64_t(length)) == AMEDIA_OK,
              let track = Self.firstAudioTrack(of: extractor)
        else {
            throw AudioFileError.unreadable(url)
        }
        defer { AMediaFormat_delete(track.format) }
        AMediaExtractor_selectTrack(extractor, track.index)

        var pcm = DecodedPCM()
        pcm.take(track.format, encoding: false)
        guard let codec = AMediaCodec_createDecoderByType(track.mime) else {
            throw AudioFileError.unreadable(url)
        }
        defer { AMediaCodec_delete(codec) }
        guard AMediaCodec_configure(codec, track.format, nil, nil, 0) == AMEDIA_OK,
              AMediaCodec_start(codec) == AMEDIA_OK
        else {
            throw AudioFileError.unreadable(url)
        }
        defer { AMediaCodec_stop(codec) }

        var inputEnded = false
        // How long the decoder may go without giving anything, in 10 ms
        // waits, before the file counts as one it cannot read.
        var idle = 0
        while idle < 500 {
            if !inputEnded {
                let index = AMediaCodec_dequeueInputBuffer(codec, 10_000)
                if index >= 0 {
                    var capacity = 0
                    let buffer = AMediaCodec_getInputBuffer(codec, Int(index), &capacity)
                    let read = AMediaExtractor_readSampleData(extractor, buffer, capacity)
                    if read < 0 {
                        AMediaCodec_queueInputBuffer(codec, Int(index), 0, 0, 0, UInt32(AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM))
                        inputEnded = true
                    } else {
                        let time = UInt64(max(0, AMediaExtractor_getSampleTime(extractor)))
                        AMediaCodec_queueInputBuffer(codec, Int(index), 0, Int(read), time, 0)
                        AMediaExtractor_advance(extractor)
                    }
                }
            }
            var info = AMediaCodecBufferInfo()
            let index = AMediaCodec_dequeueOutputBuffer(codec, &info, 10_000)
            if index >= 0 {
                var size = 0
                if info.size > 0, let buffer = AMediaCodec_getOutputBuffer(codec, Int(index), &size) {
                    try pcm.append(UnsafeRawPointer(buffer + Int(info.offset)), byteCount: Int(info.size), url: url)
                }
                AMediaCodec_releaseOutputBuffer(codec, Int(index), false)
                if info.flags & UInt32(AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) != 0 {
                    guard pcm.sampleRate > 0, let first = pcm.channels.first, !first.isEmpty else {
                        throw AudioFileError.unreadable(url)
                    }
                    return AudioClip(sampleRate: pcm.sampleRate, channels: pcm.channels)
                }
                idle = 0
            } else if index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED, let format = AMediaCodec_getOutputFormat(codec) {
                pcm.take(format, encoding: true)
                AMediaFormat_delete(format)
            } else {
                idle += 1
            }
        }
        throw AudioFileError.unreadable(url)
    }

    private static func firstAudioTrack(of extractor: OpaquePointer) -> (index: Int, format: OpaquePointer, mime: String)? {
        for index in 0..<AMediaExtractor_getTrackCount(extractor) {
            guard let format = AMediaExtractor_getTrackFormat(extractor, index) else { continue }
            var mime: UnsafePointer<CChar>?
            if AMediaFormat_getString(format, nucleant_format_key_mime(), &mime), let mime,
               String(cString: mime).hasPrefix("audio/") {
                return (index, format, String(cString: mime))
            }
            AMediaFormat_delete(format)
        }
        return nil
    }
}

/// `android.media.AudioFormat`'s `ENCODING_PCM_*`: what a decoder's output
/// format says its samples are.
private enum PCMEncoding: Int32 {
    case pcm16 = 2
    case pcm8 = 3
    case float = 4
    case pcm24Packed = 21
    case pcm32 = 22
}

/// The decoder's output so far, one array per channel, and its format as it
/// last said.
private struct DecodedPCM {
    var sampleRate = 0.0
    var channels: [[Float]] = []
    private var encoding = PCMEncoding.pcm16
    private var unknownEncoding: Int32?

    /// The rate and channel count `format` gives, and — for an output format,
    /// which only it states — the encoding.
    mutating func take(_ format: OpaquePointer, encoding: Bool) {
        var value: Int32 = 0
        if AMediaFormat_getInt32(format, nucleant_format_key_sample_rate(), &value), value > 0 {
            sampleRate = Double(value)
        }
        if AMediaFormat_getInt32(format, nucleant_format_key_channel_count(), &value), value > 0, channels.isEmpty {
            channels = [[Float]](repeating: [], count: Int(value))
        }
        if encoding, AMediaFormat_getInt32(format, nucleant_format_key_pcm_encoding(), &value) {
            if let known = PCMEncoding(rawValue: value) {
                self.encoding = known
                unknownEncoding = nil
            } else {
                unknownEncoding = value
            }
        }
    }

    /// Interleaved samples, as `encoding` says, onto the channels.
    mutating func append(_ bytes: UnsafeRawPointer, byteCount: Int, url: URL) throws {
        guard unknownEncoding == nil, !channels.isEmpty else { throw AudioFileError.unreadable(url) }
        let channelCount = channels.count
        let width = switch encoding {
        case .pcm8: 1
        case .pcm16: 2
        case .pcm24Packed: 3
        case .float, .pcm32: 4
        }
        let frames = byteCount / (width * channelCount)
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                let at = (frame * channelCount + channel) * width
                let sample: Float = switch encoding {
                case .pcm8: (Float(bytes.load(fromByteOffset: at, as: UInt8.self)) - 128) / 128
                case .pcm16: Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: at, as: Int16.self))) / 32_768
                case .pcm24Packed:
                    Float(Int32(bitPattern: UInt32(bytes.load(fromByteOffset: at, as: UInt8.self)) << 8
                        | UInt32(bytes.load(fromByteOffset: at + 1, as: UInt8.self)) << 16
                        | UInt32(bytes.load(fromByteOffset: at + 2, as: UInt8.self)) << 24) >> 8) / 8_388_608
                case .pcm32: Float(Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: at, as: Int32.self))) / 2_147_483_648
                case .float: Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
                }
                channels[channel].append(sample)
            }
        }
    }
}
