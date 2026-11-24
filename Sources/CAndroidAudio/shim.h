#pragma once

// AAudio for the output, the NDK's media extractor and codecs for the
// decoder. Pulled in through a module map rather than a compiled target:
// these are NDK headers, already present in the Swift Android SDK's sysroot,
// and libaaudio.so and libmediandk.so are linked below.
#include <aaudio/AAudio.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>

// The format keys the decoder reads and sets. AMEDIAFORMAT_KEY_* are
// `extern const char *` — mutable globals, which Swift 6 will not read
// outside an actor — so these hand them over.
static inline const char *nucleant_format_key_mime(void) { return AMEDIAFORMAT_KEY_MIME; }
static inline const char *nucleant_format_key_sample_rate(void) { return AMEDIAFORMAT_KEY_SAMPLE_RATE; }
static inline const char *nucleant_format_key_channel_count(void) { return AMEDIAFORMAT_KEY_CHANNEL_COUNT; }
static inline const char *nucleant_format_key_pcm_encoding(void) { return AMEDIAFORMAT_KEY_PCM_ENCODING; }
