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
| WebAssembly | Web Audio (AudioWorklet), via JavaScriptKit  | `decodeAudioData`, waited on with JSPI |

On Linux, libasound and libsndfile are opened at run time. Building needs
neither one's headers, and a machine without them gets
`outputUnavailable` or `decoderUnavailable` instead of an app that won't
start.

In a browser both go through JavaScriptKit, so the page has to load
JavaScriptKit's runtime. NucleantApplication's page does that for any module
built with JavaScriptKit.

- The browser holds back sound until the page has had a user gesture, so an
  output started before one begins at the first click, touch or key press.
- The browser's decoder only answers through a Promise. Loading waits for it
  under JSPI (WebAssembly JavaScript Promise Integration) through
  NucleantApplication's page, and throws `decoderUnavailable` in a browser
  without JSPI. It has to be called from code the page called into (an
  event, a frame, a task), not from inside a JavaScript callback.
- The browser's decoder converts to the rate it decodes for and never says
  the file's own. A WAV or FLAC file states its rate in its header, so it
  comes back at that rate, its samples unchanged; any other comes at 48 kHz.
