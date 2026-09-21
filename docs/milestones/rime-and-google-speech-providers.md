# Rime and Google speech providers

Status: implementation pending. This milestone extends the completed provider-package and
semantic-speech contracts with working speech capabilities. A capability appears in the setup
catalog only after its adapter passes the contract and call-consumer checks.

Prerequisites: [Simpler speech integrations](simpler-speech-integrations.md),
[Provider integration packages](provider-integration-packages.md), and
[Tenant-scoped provider credentials](tenant-provider-credentials-and-platform-configuration.md).

Design sources: [speech provider contract](../speech-provider-contract.md),
[provider comparison](../speech-provider-comparison.md), and
[provider integration packages](../provider-integration-packages.md). The Deepgram API refinement
is recorded in [voice selection](../deepgram-voice-selection.md).

## Runnable outcome

A call spec can select Rime Coda TTS or Google AI Studio TTS/STT through the same scoped speech
sessions as Deepgram. Credentials resolve through the existing tenant/platform binding. No
provider has a fallback to another provider or a credential-only badge. The setup UI exposes
only capabilities that run in this build, with capability tags wrapping on service cards.

## Design review

- [x] Keep complete-text TTS requests and existing bounded audio delivery. The engine owns
  cancellation, playback and permission decisions; each provider owns its wire protocol.
- [x] Use Rime's Coda JSON WebSocket with `segment=never`, one complete text and one explicit
  flush per request. It streams raw PCM and emits one `done` for that serialized batch. The socket
  can prepare during activation, avoiding a new handshake on every spoken turn. On cancellation,
  retire the socket unless provider evidence confirms that old generation cannot leak into the
  next request; `clear` alone is insufficient.
- [x] Use Google's dedicated speech models, not general Gemini inference as an invented STT
  endpoint. Streaming TTS audio and live transcription have separate APIs and lifecycles.
- [x] Keep conversational STT's existing requirement for provider turn ending and prompt
  speech-start evidence. Do not infer user turns from a timer or transcript-only completion.
- [x] Keep credentials out of tests, logging, status and documentation. Live checks resolve saved
  encrypted credentials only inside a local command and print safe outcome/timing metadata.
- [x] Name provider-facing session APIs after the capability, not the current model family.
  Keep `coda` and Deepgram Flux model names in selection/configuration and wire translation.
  Deepgram TTS call specs will select a voice; the provider will construct its wire model.
- [x] Establish each provider capability with a failing focused contract test, then implement and
  commit the complete provider slice with configuration, session, registry, call consumer and UI.

Rejected alternatives: mapping Rime `clear` to confirmed cancellation (it only clears buffered
text); advertising Google's older audio-understanding response as real-time turn detection; and
adding a common all-provider socket/process layer. Rime streaming HTTP was considered for its
single-response boundary, but a one-utterance live probe measured 1,471 ms to first audio on a
fresh request. A prepared JSON WebSocket measured 1,387 ms connection preparation followed by
538 ms from submit to first audio. Those single samples motivate the transport choice, not a
general performance claim. The existing bounded Mint socket machinery can be shared without
changing call ownership. [Rime streaming HTTP](https://docs.rime.ai/api-reference/coda/http) and
[Rime JSON WebSocket](https://docs.rime.ai/api-reference/coda/websockets-json) specify the wire
formats and `done` semantics.

## Checkpoint A — Rime TTS

- [x] Prove the saved credential can synthesize a short utterance as raw PCM at the selected
  sample rate; record first-audio and completion without audio or secret output. Cancellation
  remains to be verified with the session.
- [x] Add pure Rime TTS option validation and a semantic TTS session with bounded request and
  read deadlines, bounded audio credit, request-scoped cancellation and safe status/error output.
- [x] Register `:tts`, accept Rime call-spec selections/settings, and exercise activation and
  playback through project-owned integration tests. Room barge-in and cleanup still need the
  checkpoint exit's broader checks.
- [x] Update provider capability tags and setup choices after a working live semantic session.
- [ ] Exit: focused Rime/provider/call tests, rendered desktop/mobile services, bounded load
  comparison, and root gates pass; commit one provider checkpoint.

## Checkpoint A2 — Deepgram capability APIs and voice selection

- [x] Register provider-level `STTSession` and `TTSSession` while retaining the tested Flux wire
  decoder privately. Do not add compatibility aliases or a parallel runtime.
- [x] Accept `model: "flux"` plus `options.voice` for TTS and construct the wire model in the
  Deepgram provider. Reject a missing or malformed voice. Keep explicit full model selections
  valid for published, immutable call-spec revisions; do not rewrite stored sources.
- [x] Exercise selection, connection URL, inline credential activation and demo sample call
  specs with focused red-green tests.
- [ ] Run affected provider/engine/console/persistence/gateway checks, root gates and bounded
  Deepgram call load; document the result and commit the provider checkpoint.

## Checkpoint B — Google AI Studio TTS

- [ ] Prove the saved credential can access the current dedicated TTS model and inspect streamed
  PCM format, first-audio and completion events without printing audio or secrets.
- [ ] Add pure Google TTS options and a semantic session that maps request and terminal events,
  validates audio framing, preserves credit and retires cancelled generations safely.
- [ ] Register `:tts`, accept Google TTS selections/settings, and test activation, cancellation,
  playback and failure at the call boundary.
- [ ] Update Google setup choices/tag and verify rendered services; run bounded load and root
  gates; commit one provider checkpoint.

## Checkpoint C — Google AI Studio live STT

- [ ] Probe the current transcription Live API using synthetic PCM. Verify a real provider turn
  end and measure first usable speech-start/interim latency against current barge-in behavior.
- [ ] Add a scoped semantic STT session, reconnect/session-expiry handling, bounded audio
  admission, turn correlation and safe failure cleanup. No artificial turn-end timers.
- [ ] Register `:stt`, validate Google STT call selections and test speech permission changes,
  barge-in, endpointing, connection loss and room teardown.
- [ ] Show STT only after those gates pass; run bounded load, rendered services and root gates;
  commit one provider checkpoint. If the protocol cannot provide the required turn evidence,
  leave STT unavailable and record the measured blocker rather than weakening the call contract.

## Final acceptance

- [ ] Reconcile capability manifest, setup catalog, call-spec choices, provider author guide and
  this checklist with implemented behavior.
- [ ] Verify existing Deepgram, Morse and telephony regressions and compare bounded concurrent
  delivery/turn latency with baseline. Do not exceed roughly half the local system resources.
- [ ] Run all umbrella completion gates and the relevant frontend/browser checks. Verify saved
  service records survived unchanged, inspect the final diff and commit the final documentation.
