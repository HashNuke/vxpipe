# Bundled wait-sound sources

Call Engine packages these assets for web, phone and embedded participants. Call specs
select defaults by omission, silence with null / Elixir `nil`, or a custom HTTP(S) file URL.
Authored configuration never selects these local filenames. See the
[transfer readiness milestone](../../../../../docs/milestones/transfer-readiness-and-wait-sounds.md).

| File | Packaged format | Duration | SHA-256 |
| --- | --- | --- | --- |
| `cafe-bossa.wav` | Stereo, 48 kHz PCM16 little-endian | 9 seconds | `c905d5a0acbe01d2d992c08708b4d079b17e50a240e8d1220a1ddb659718efd1` |
| `phone-ring.wav` | Stereo, 48 kHz PCM16 little-endian | 9 seconds | `828699704571814b61b5385a17f7b99091f65771b93fb21d75d562d74cb913a5` |
| `connection-cue.wav` | Mono, 48 kHz PCM16 little-endian | 250 ms | `65ba012274aae1c8da4bb624518f01a1a1a1d7faa7753346b710b1f2071f0712` |

The two loops preserve all 432,000 stereo frames from the
[authoring originals](../../../../../sounds/README.md). The original ChucK output declared the
RIFF size as the complete 1,728,044-byte file size. The engine copies correct that four-byte field
to 1,728,036 (file size minus eight); every other byte remains identical. Preserve intentional
ringtone pauses and avoid fading at repeat boundaries.

Preparation strictly validates mono/stereo 48 kHz PCM16 WAV files and averages stereo pairs once
using signed integer division, with no gain increase or clipping. It caches the canonical mono
result. Opening audio continues to require mono unless its caller explicitly selects stereo
normalization. Invalid remote RIFF sizes are rejected; there is no permissive decoder fallback.
Resolve built-ins with `Application.app_dir(:vxpipe_call_engine, "priv/audio/wait_sounds/...")`,
independently of the working directory. The prepared manifest deduplicates normalized bytes and
pins their digest and normalization profile; per-participant players will own separate cursors.

The finite connection cue is a 1 kHz sine, 12,000 samples, at a -6 dBFS peak, with 240-sample
(5 ms) linear ramps at each end. Its samples are generated with this expression, for sample index
`i` from 0 through 11,999, then written as signed PCM16 little-endian in a mono 48 kHz WAV:

```python
round(32767 * 10**(-6/20) * min(1, i/240, (11999-i)/240)
      * math.sin(2*math.pi*1000*i/48000))
```

The cue remains present when every wait slot is nil. Preparation tests verify the cue duration
and peak, built-in normalization and waveform preservation. Playback orchestration and rendered
web/phone audibility verification remain milestone acceptance work.
