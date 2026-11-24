# Move NucleantAudio

we need NucleantUI/Sources/NucleantAudio moved into its own repo (this)
and i guess new branch on nucleantui and pr for its removal 
keep Sampler / Metronome here but just make them target NucleantAudio package instead..
master / local for now

in general i dont think UI and Audio belongs same place..
only the Examples using it should be the exception

# Package.swift + cross-platform
so far Package.swift ability to only include targets as dependencies, if specific platform
havnt been utilized really and needs to change now atleast here...

```swift
// Package.swift
        .target(
            name: "NucleantAudio",
            dependencies: [
                .byName(name: "LinuxAudio", condition: .when(platforms: [.linux])),
                .byName(name: "AndroidAudio", condition: .when(platforms: [.android])),
                .byName(name: "AppleAudio", condition: .when(platforms: [.macOS, .iOS, .visionOS, .tvOS, .watchOS])),
                .byName(name: "WasmAudio", condition: .when(platforms: [.wasi])),
                .byName(name: "WindowsAudio", condition: .when(platforms: [.windows])),
            ]
        ),
```

now it should be easy to write each handler / wraparound 

# AudioProtocols
all protocols that needs to be sharable between XxxAudio and NucleantAudio
should be defined in AudioProtocols
like

* NucleantAudio/Sources/AudioProtocols/AudioProcessor.swift

and now AppleAudio, AndroidAudio, LinuxAudio etc. all imports AudioProtocols
to add the AudioProcessor part..

each platform target can also just fill out by extension the protocols requirements
and just afterwards make a "default" handler for each platform,
that final NucleantAudio is using kinda like now
but shouldnt require the same #if os 
guards for a whole file etc, besides ofc what do needs to be habdled pr platform in 


# NucleantDSP

not made yet (only repo made no package yet), but example this future library should now just need 
AudioProtocols target from NucleantAudio to understand what each
DSP Node or whatever we end up defining in here, conforms to some of the protocols
sooo NucleantAudio + DSP works on every platform without envolve the different XxxAudio platform targets

https://developer.apple.com/documentation/swift/mutablespan

audio / dsp packages should both use swift 6.3
and if any benefits using new span / mutable span we should do so..

## dsp + simd
i guess apples simd when on apple platforms and kvSIMD on other platforms..
https://github.com/keyvariable/kvSIMD.swift

else nucleantdsp should be pretty platform nuetral besides the simd depdency part..
and same conditional part can be used to not include it on apple platforms, but all the others..

## make processors both in swift, c , vult (becomes c)

https://github.com/vult-dsp/vult/tree/master/examples

use vult and its examples / other examples on the net to generate
processor nodes or whatever we should consider each thing

any good existing c code that does it could also be considered..

but all of them should afterwards be added in NucleantDSP target where they conform
to protocols from AudioProtocols in NucleantAudio..

