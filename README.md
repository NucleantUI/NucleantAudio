# NucleantAudio

Audio file loading and playback for Swift, with one API on every platform.
Write what makes the sound once, as an `AudioProcessor`. `AudioPlayer`
runs it on each platform's own output device.

```swift
.package(url: "https://github.com/NucleantUI/NucleantAudio.git", branch: "master")
```

## Use

```swift
import Foundation
import NucleantAudio

struct Tone: AudioProcessor {
    var frequency = 440.0
    private var phase = 0.0

    mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        for frame in 0..<(buffer.count / channels) {
            let sample = Float(sin(phase * 2 * .pi)) * 0.2
            phase = (phase + frequency / sampleRate).truncatingRemainder(dividingBy: 1)
            for channel in 0..<channels {
                buffer[frame * channels + channel] = sample
            }
        }
    }
}

let player = try AudioPlayer(Tone(), channels: 2)
try player.start()
player.withProcessor { $0.frequency = 880 }  // lands between two buffers
```

`AudioFileLoader().load(contentsOf:)` reads a file into an `AudioClip`,
and `ClipPlayback` is the processor that plays one.

## Layout

- **AudioProtocols** (also a product): `AudioProcessor`, `AudioClip`, the
  errors, and the protocols a platform implements (`AudioOutput`,
  `AudioDecoder`, `AudioRenderer`). A package that makes sound without
  playing it depends on this alone.
- **AppleAudio, LinuxAudio, AndroidAudio, WindowsAudio, WasmAudio**: one
  per platform. Package.swift picks the target by platform, so a build
  compiles only its own. Each one declares the same `DefaultAudioOutput` and
  `DefaultAudioDecoder`.
- **NucleantAudio**: `AudioPlayer`, `AudioFileLoader` and `ClipPlayback`,
  built on whichever platform target the build has.

## Platforms

| Platform    | Output                                        | Decoder                              |
|-------------|-----------------------------------------------|--------------------------------------|
| macOS       | AVAudioEngine                                 | AVAudioFile                          |
| iOS         | AVAudioEngine, `AVAudioSession` `.playback`   | AVAudioFile                          |
| Linux       | ALSA's default PCM (PipeWire, PulseAudio)     | libsndfile                           |
| Android     | not yet: throws `unsupportedPlatform`         | not yet: throws `unsupportedPlatform` |
| Windows     | not yet: throws `unsupportedPlatform`         | not yet: throws `unsupportedPlatform` |
| WebAssembly | not yet: throws `unsupportedPlatform`         | not yet: throws `unsupportedPlatform` |

On Linux, libasound and libsndfile are opened at run time. Building needs
neither one's headers, and a machine without them gets
`outputUnavailable` or `decoderUnavailable` instead of an app that won't
start.
