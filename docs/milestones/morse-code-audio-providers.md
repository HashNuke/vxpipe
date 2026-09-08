# Local Morse-code audio providers

Status: not implemented. Specification review: approved (2026-09-08).
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

- [ ] Write failing independent known-signal decode tests and expected tone/silence encode tests before implementing the codec.
- [ ] Implement bounded incremental Morse encoding/decoding with documented normalization and invalid-input behavior.
- [ ] Add local STT/TTS provider/transport adapters and closed-registry configuration, preserving current hosted adapters.
- [ ] Drive an actual room audio ingress-to-transcript and text-to-audio egress path using a deterministic reply fixture.
- [ ] Document an opt-in sample/embedded profile, encoded input method, audio safety settings and supported transport limitations.

## Acceptance and failure checks

- [ ] Known external/reference-derived signal fixtures decode correctly; expected sample runs verify encoding independently. A same-codec round trip alone is insufficient.
- [ ] Arbitrary chunk boundaries, split PCM samples, word gaps, trailing flush, empty input and incomplete final symbols have documented deterministic outcomes.
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

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08. Approved the deterministic
real-audio outcome, independent fixtures, provider boundary adaptation and explicit
codec/browser limitations; second index position is appropriate and optional.
Index and architecture cross-references now distinguish the plan from implemented adapters.
This is specification evidence only; implementation and runtime verification remain unchecked.
