# Bundled wait-sound sources

These original assets are copied unchanged from the repository's authoring `assets/` directory
for the proposed [transfer readiness and wait-sound milestone](../../../../../docs/milestones/transfer-readiness-and-wait-sounds.md).
Call Engine owns them so both web and phone adapters, as well as embedded hosts, can use them.
Runtime selection and playback are still to be implemented.

| File | Format | Duration | SHA-256 |
| --- | --- | --- | --- |
| `cafe-bossa.wav` | Stereo, 48,000 Hz, signed PCM16 little-endian | 9 seconds | `c20f5348c47cd92d5d9ef6206a37ae9bcbad16f3767b4d92b392a0eb334f6aad` |
| `phone-ring.wav` | Stereo, 48,000 Hz, signed PCM16 little-endian | 9 seconds | `3e7b1bc36207074e140393b1d769f1868e8b10979ed4b519a5ff72e2b1a82157` |

Each file contains 432,000 stereo frames and is 1,728,044 bytes. The copies match their source
files byte for byte. The [authoring instructions](../../../../../assets/README.md) describe the
original synthesized arrangements, loop boundaries, levels and ringtone cadence. Preserve the
intentional pauses in the ringtone and avoid fading at every repeat boundary.

The existing `OpeningAudio.WaveDecoder` accepts mono, so these stereo sources cannot simply be
passed to it unchanged. The milestone will normalize to canonical 48 kHz mono PCM16 once during
asset preparation, cache the immutable result, and give each participant an independent player.
No decoder broadening or runtime conversion is included in this asset-copy checkpoint.

Resolve these built-in defaults internally using
`Application.app_dir(:vxpipe_call_engine, "priv/audio/wait_sounds/...")`; never depend on the
repository working directory or expose local paths in call definitions. The proposed call-level
`wait_sounds` accepts URLs (fetch and play), null / Elixir `nil` (silence), or omission (use these
defaults). Authored configuration does not select local asset names. Café-bossa is the default for
transfer audiences going to an AI and for incoming humans after acceptance; phone-ring is the
default for audiences going to a human and the proposed initial caller setup default. A distinct,
finite connection beep will be generated and validated during implementation.
