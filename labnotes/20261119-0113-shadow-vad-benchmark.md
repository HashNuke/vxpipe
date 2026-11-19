# Shadow VAD benchmark research

- Scope: research feasibility and non-interference; no implementation, deployment,
  provider calls or live configuration changes requested or performed.
- Initial worktree clean. Inspected local audio frames, Silero model/runtime,
  boundary classifier, conversational STT coordinator, Scribe socket/protocol,
  manual commit path and provider selection. Consulted official Silero source
  and ElevenLabs documentation.
- Existing Silero is reusable, but the operational VAD toggle changes onset and
  failure handling. It cannot serve as an isolated benchmark switch.
- Crucial measurement detail: 16 silent 32 ms frames confirm an endpoint whose
  sample position is backdated; callback wall time would understate STT delay.
- Current wrapper drops sample timestamps and acoustic end events, and resets
  its stream at provider settlement. Independent timing/correlation is needed.
- Both historical manual and provider-VAD paths exist. Effective session strategy
  must be captured, not guessed from source specs. Did not establish the historic
  call's acoustic endpoint or exact provider-receipt time.
- Recommendation and verification gates recorded in
  `docs/design/shadow-vad-latency-benchmark.md`. Offline analysis first where
  aligned recordings exist; bounded independent observer for future live data.
- No dependency/runtime work was needed; setup and runtime suites not run.
  Verification: source review, official documentation comparison, Markdown link
  and whitespace checks. No claim of measured observer overhead or accuracy.
