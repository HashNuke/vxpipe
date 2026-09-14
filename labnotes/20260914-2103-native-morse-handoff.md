# Native Morse handoff

- User direction: diagnose handoff, protocol and audio through native WebRTC clients; reuse Morse
  STT/TTS and RTVI, keeping UI work narrow. Existing Gateway tests already use ExWebRTC peers,
  real ICE/DTLS/SRTP/SCTP and HTTP signalling. Extended that fixture rather than building a second
  client framework. The model response is scripted; speech providers execute real local code.
- Behavioral red: first caller Opus packet terminated Morse STT with `unsupported_audio` because
  Gateway forwarded negotiated Opus directly while the selected provider requires linear PCM.
  The room-only Morse round trip never crossed this boundary. Evidence:
  `vxpipe-native-morse-configured.log`. An earlier fixture lacked explicit empty provider options;
  that configuration error was corrected before the audio red.
- Gateway now reads the selected provider's input format through the ingress boundary and prepares
  a native Opus decoder when PCM is required. Conversion includes mono output, provider sample rate
  and timestamps. Matching Opus providers retain passthrough. Readiness prepares the same delivered
  speech format; mixer input still uses its existing negotiated track and decoder pipeline.
- The decoder is held by the existing connection process, keyed by ingress and negotiated track.
  No new process or dependency is introduced. Unrelated policy changes reuse it. Closed admission
  and existing ingress policy checks continue to own whether audio is admitted.
- Fixture corrections: pace RTP at microphone cadence, retain sequence/encoder state between
  utterances, retain receiver Opus decoder history, and consume verified cue tails before measuring
  conversation. Bursting complete utterances through normal bounded ingress lost the terminal gap.
- Codec experiments: pristine-PCM Morse settings rejected codec boundary windows. Used existing
  configurable 60 ms units, 20 ms windows, detection threshold 2400 and 250 Hz frequency tolerance.
  No Morse provider defaults or decoder algorithm changed. Exact symbol decoding across the mixed,
  twice-encoded human bridge remained timing-sensitive even after cue-tail removal. The final
  boundary check decodes TTS reply/briefing text, verifies exact live STT transcripts, and measures
  the distinct 700 Hz conversational signal on each receiving peer. It does not claim exact symbol
  reconstruction after the second Opus encode or physical speaker audibility.
- Native 48 kHz case passed (`vxpipe-native-morse-green.log`). Switched STT to 16 kHz so the
  final test also exercises resampling. Its decoder-retention assertion caught an implementation
  mistake: RTP track IDs were integers while readiness used strings, causing a replacement during
  preparation. Normalizing both paths to the existing string identity fixed this; the native case
  now passes within the full 19-case run.
- The first full 19-case run passed the native case but failed an existing phase-loss recovery
  before its 750 ms budget elapsed (`vxpipe-native-morse-and-progress-all.log`). The first root
  run reproduced it; focused four-case recovery and a full 19-case run with error-only instrumentation
  passed (`vxpipe-native-recovery-focused.log`, `vxpipe-native-all-recovery-probe.log`). The exact
  failing recovery step was not established. Removed the probes; no recovery algorithm, deadline
  or production buffer sizes were changed. Keep phase-loss intermittency in the remaining failure
  acceptance work.
- Final uninstrumented worktree passes all five root gates: formatting, ordinary warnings-as-errors
  compile, strict Credo, unused-lock check, and 1,303 tests with zero failures and 15 exclusions,
  seed 355428 at concurrency four. Gateway contributes 335 tests including all 19 native transfer
  cases. Logs use the `vxpipe-native-checkpoints-final-` prefix. No temporary probes remain.
- Updated the milestone's verification method per the revised objective: native WebRTC/RTVI owns
  backend acceptance, while browser inspection applies to necessary UI/browser-specific work.
  Recorded this review separately from implementation evidence. Phone-provider and physical
  speaker evidence remain distinct; no runtime requirements were reduced.
- Normal dev compilation initially hit the previously observed consolidated-Inspect cache warnings.
  Forced compilation cleared them without dependency changes; the subsequent ordinary
  warnings-as-errors compilation passes (`vxpipe-native-checkpoints-compile-force.log`).
