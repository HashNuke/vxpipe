# Public speech samples

The two `final_word` files contain “The final word is telescope.” generated
with Deepgram `aura-2-thalia-en`. They contain no caller recording or credential.

- `final_word_16k_mono_s16le.pcm`: raw 16 kHz mono signed little-endian PCM,
  133,120 bytes / 4.16 seconds, including two seconds of trailing silence.
- `final_word_48k_mono_opus.ogg`: local FFmpeg transcoding to 48 kHz mono Opus
  in an Ogg container, for packet-based WebRTC tests.

Selected live tests call `Vxpipe.Providers.Deepgram.LiveFixture.ensure!/0`.
Existing samples are reused; missing PCM requires one TTS request, and missing
Opus is derived locally. The silence tail allows automatic turn completion.
Review regenerated samples before committing them.

`short_answer_16k_mono_s16le.pcm` contains the fixed public phrase "Yes.",
generated with the same `aura-2-thalia-en` model: raw 16 kHz mono signed
little-endian PCM, 19,200 bytes / 600 ms, with no appended silence.
`Vxpipe.Providers.Deepgram.LiveFixture.ensure_short!/0` generates it with one
TTS request only when missing, then reuses the saved file. Tests supply their
own trailing quiet input. Sample review found no clipped samples; the selected
ElevenLabs short-answer live case recognized the expected word.

Bounded live Flux Opus and RTVI checks passed individually with this sample.
Those checks establish the adapter's provider protocol; configured-service and
phone acceptance are separate.
