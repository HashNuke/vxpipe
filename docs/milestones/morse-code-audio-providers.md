# Local Morse-code audio providers

Status: implementation in progress. Specification review: approved (2026-09-08).
Prerequisites: [Definition-driven call](definition-driven-call.md). This early optional provider slice does not become a semantic prerequisite for later production features.
Sources: User-requested local testing/verification addition; [provider capability boundary](../architecture.md); [International Morse code, ITU-R M.1677-1](https://www.itu.int/rec/R-REC-M.1677-1-200910-I/en). Verify the normative timing/alphabet against the recommendation during implementation.

## Runnable outcome

A developer selects `MorseCodeTTS` and `MorseCodeSTT` through ordinary capability configuration. Known text becomes audible tones, injected encoded audio becomes transcript events, and a deterministic local reply completes an audio round trip without hosted STT/TTS credentials.

## Specification

- These are opt-in in-process providers for development, testing and deliberate application use, not mocks that skip audio. MorseCodeTTS encodes a documented text alphabet into PCM tones; MorseCodeSTT decodes that supported tone signal into text. It does not recognize ordinary human speech.
- Implement the existing STT/TTS capability boundaries and normal media frames/signals. Current provider contracts include transport/connection operations; supply local transport implementations or make the smallest tested boundary adjustment needed, without a pretend external URL, a local network server, or bypassing lifecycle/interruption controls.
- Document the supported alphabet, case/whitespace normalization, punctuation behavior, timing, tone frequency, bounded amplitude, sample formats and decoder tolerances. Unsupported text, invalid configuration and malformed/incomplete signals get explicit bounded outcomes; never silently invent recognized speech. Exact Morse tables/timing must match independent reference fixtures.
- Preserve streaming state across arbitrary PCM chunks and split tone/silence intervals. Specify how end-of-input or an explicit flush completes a final character/word/utterance without dropping its tail; silence-only input produces no fabricated transcript. Keep detector buffers and pending output bounded.
- Reuse real turn, participant, activation, playback generation and interruption boundaries. Cancelling speech clears unplayed tones and stale output cannot contaminate a later turn. Emit recognition/final-turn signals only from supported decoding outcomes. If word timing is exposed, derive it from actual generated sample offsets and the existing playout boundary, not invented text-character estimates.
- No hosted speech API keys or network connection are needed. A fully offline conversation also uses a deterministic local model-inference fixture; selecting a hosted LLM still requires that LLM. Do not mislabel zero external speech charges as a provider-reported monetary value.
- Keep deterministic PCM loopback separate from lossy codecs, browser microphone processing and acoustic echo. Prove the direct PCM contract first; explicitly test/document any supported codec/WebRTC path and tolerances. Injected/file-based encoded input is valid; ordinary microphone speech is not a Morse test.
- Select providers through the same closed registry/typed definition path as other implementations. Keep default application voices unchanged. The sample can use a documented fixture/profile without adding persistent controls to its responsive console.

## Implementation checklist

- [x] Write failing independent known-signal decode tests and expected tone/silence encode tests before implementing the codec.
- [ ] Implement bounded incremental Morse encoding/decoding with documented normalization and invalid-input behavior.
- [ ] Add local STT/TTS provider/transport adapters and closed-registry configuration, preserving current hosted adapters.
- [ ] Drive an actual room audio ingress-to-transcript and text-to-audio egress path using a deterministic reply fixture.
- [ ] Document an opt-in sample/embedded profile, encoded input method, audio safety settings and supported transport limitations.

## Acceptance and failure checks

- [x] Known external/reference-derived signal fixtures decode correctly; expected sample runs verify encoding independently. A same-codec round trip alone is insufficient.
- [x] Arbitrary chunk boundaries, split PCM samples, word gaps, trailing flush, empty input and incomplete final symbols have documented deterministic outcomes.
- [ ] Invalid alphabet/configuration and bounded buffer/oversized input failures are explicit; no silent truncation or unlimited queue growth.
- [ ] Long output drains fully; an interruption drops only unplayed prior-generation output and a subsequent utterance still works.
- [ ] Turn/participant attribution and final transcript boundaries remain correct across repeated messages; timing, if emitted, follows generated audio samples.
- [ ] End-to-end local fixture succeeds without speech credentials or network access; no provider-default change or ordinary-speech-recognition claim.
- [ ] Direct PCM tests and any claimed codec/browser integration run separately; microphone DSP/echo limitations are recorded, not concealed by loopback success.

## Manual verification

1. Select the documented local Morse provider profile and deterministic reply fixture; leave hosted speech credentials unset.
2. Inject an independently generated supported phrase as encoded audio; inspect the recognized user text and hear the encoded reply at a modest volume.
3. Submit two text turns, then interrupt a longer reply. Verify clean transcript rows, complete tone output and no stale audio in the next turn.
4. If a WebRTC/codec path is offered, test it explicitly with the documented input method and settings; distinguish it from direct PCM verification.

## Scope boundaries

No hosted speech dependency, speech ML model, local VAD, general human-language recognition, arbitrary acoustic robustness, new client protocol, or replacement for real-provider interoperability checks. This milestone adds an optional audio verification tool, not an alternative architecture.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence, checkpoint 1 (2026-09-09): added the independent in-process codec
foundation without changing provider selection or application defaults. The encoder renders
bounded 16-bit little-endian mono PCM from normalized supported text using the ITU 1:3 mark and
1:3:7 spacing ratios. The incremental decoder retains partial samples/windows across arbitrary
binary chunks, identifies the configured tone, and emits explicit start/partial/final results.
Its default 14-unit local end gap is deliberately distinct from the ITU seven-unit word gap and
provides deterministic utterance completion.

The first focused run failed because the codec modules did not exist. The green run passes two
tests: an expected-run assertion for normalized `ET A`, and a hand-authored square-wave `SOS 2`
fixture split at odd byte boundaries so the decoder is not validated by its own encoder. A
warnings-as-errors child compile also passes. Exhaustive alphabet, malformed/bounded input,
flush and timing-tolerance checks remain pending before the codec checklist items are complete.

Implementation evidence, checkpoint 2 (2026-09-09): expanded the codec contract to the complete
documented ASCII subset of the ITU table and explicit boundary outcomes. The new red run exposed
two gaps: non-binary PCM raised a function-clause error, and invalid UTF-8 was misclassified as an
unsupported character. Both now return `:invalid_audio` and `:invalid_text` respectively. The
eight-test focused suite also covers invalid sampling/frequency/amplitude/timing/size settings,
empty and unsupported text, encoded-output limits, explicit tail flush, repeated flush, silence-
only input, an incomplete PCM sample, invalid mark length, wrong frequency, unsupported signal,
the undecided-signal time bound, and the documented one-window timing tolerance. These checks
complete the independent-fixture and chunk/tail acceptance items; streaming encoder output and
transport queue bounds remain pending.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08. Approved the deterministic
real-audio outcome, independent fixtures, provider boundary adaptation and explicit
codec/browser limitations; second index position is appropriate and optional.
Index and architecture cross-references now distinguish the plan from implemented adapters.
This is specification evidence only; implementation and runtime verification remain unchecked.
