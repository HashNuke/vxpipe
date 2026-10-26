# ElevenLabs Realtime speech-to-speech

Status: complete. Mini passed two native turns on one connection after the fixes;
Max passed one native turn. All common gates and final independent review pass.
The reviewed implementation is recorded in five coherent checkpoint commits.

## Outcome and constraints

Select `elevenlabs` STS with `eleven_realtime_v1_mini` or
`eleven_realtime_v1_max`, using an API key, prompt, voice and room-owned tools.
Keep one standalone Realtime connection per allocation. ElevenLabs owns speech
and semantic turn detection: no Silero or other local VAD is required or started.
Do not restore hosted-agent provisioning. Live verification uses only ElevenLabs,
existing recorded audio and the provider test runner; no real telephony.

## Prerequisites and approved contracts

- Existing [agent STS boundary](agent-speech-to-speech.md),
  [provider packages](provider-integration-packages.md), and
  [persistent sessions](persistent-speech-sessions.md).
- [Semantic provider contract](../../docs/speech-provider-contract.md),
  [author guide](../../docs/speech-integration-guide.md),
  [output admission](../../docs/sts-output-admission.md), and
  [scoped ownership](../../docs/speech-session-ownership.md).
- ElevenLabs [Realtime compatibility guide](https://elevenlabs.io/docs/eleven-agents/guides/openai-realtime-compatibility)
  and [client-secret API](https://elevenlabs.io/docs/api-reference/conversations/create-client-secret).

## Checkpoints

- [x] A — Pure model configuration and private authentication
  - [x] Confirm standalone endpoint, model identifiers and native semantic VAD.
  - [x] Write and run failing focused configuration/codec/auth tests.
  - [x] Validate public models, voices and bounded private prompt/tools.
  - [x] Mint short-lived credentials without agent resources; redact failures.
  - [x] Record API decisions, rejected alternatives and limitations under `docs/`.
- [x] B — Scoped persistent STS session
  - [x] Add supervised asynchronous startup and provider-acknowledged readiness.
  - [x] Native speech-start, transcript and turn-end events with exact identities.
  - [x] Explicit text and opening input with accepted-input evidence.
  - [x] Response-context correlation, output admission and bounded PCM credit.
  - [x] Final transcript/completion, cancellation, stale-event fencing and cleanup.
  - [x] Bounded room-authorized tools, results and cancellation.
  - [x] Fake transport tests for races, failures, limits and multiple turns.
- [x] C — Selectable model provider without local VAD
  - [x] Register manifest, catalog, public options and private runtime activation.
  - [x] Verify both models resolve existing ElevenLabs API-key credentials.
  - [x] Prove configured/compiled STS startup without a local VAD selection.
  - [x] Verify affected forms in a rendered browser if UI behavior changes.
- [x] D — Bounded ElevenLabs-only live acceptance
  - [x] Add separately selectable provider integration tests using recorded PCM.
  - [x] Ensure selecting the new file needs only ElevenLabs credentials.
  - [x] Run one short Mini and one short Max session, with no paid retries unless
    a concrete defect fix requires a targeted rerun; record actual requests/results.
  - [x] Refresh Mini acceptance after review fixes with two native turns on one connection.
  - [x] Document the narrow command and any account/API limitations.
- [x] E — Verification, independent review and small commits
  - [x] Format, compile with warnings as errors, strict Credo, full default tests,
    dependency unlock check and Lean speech-state verification pass.
  - [x] Initial independent GPT-6 Astra xhigh review of code, tests and contract claims.
  - [x] Resolve findings and receive a clean final independent review.
  - [x] Inspect staged diffs and commit coherent checkpoints with their evidence.
  - [x] Synchronize this checklist and the milestone index with final evidence.

## Design review (separate from implementation)

Initial dependency review: the STS engine already owns authorization, playback,
source attribution and tool execution. The adapter must supply semantic events,
bounded admission and private protocol identity. Catalog publication follows
the working adapter, not an advertised configuration-only stub. Provider-native
VAD satisfies the no-local-detector requirement. Authentication and event
compatibility require hosted evidence; documentation alone is insufficient.
Independent GPT-6 Astra xhigh design/code review identified the issues below;
follow-up review verified the fixes and is clean. The design pins one authorization
context per allocation; source/policy/hold cutover requires a fresh allocation
because the API does not prove complete input-buffer consumption.

## Independent review findings — 2026-10-26

Initial GPT-6 Astra xhigh review identified eight issues; none are waived:

- [x] R1: prevent metadata-free responses from borrowing another authorization origin.
- [x] R2: older caller completion must not clear later accepted audio obligations.
- [x] R3: tool-only responses must not create empty playback turns.
- [x] R4: allocate response ordinals when output is announced, not when queued.
- [x] R5: ignore cancelled-response tool tails while retaining terminal isolation.
- [x] R6: retain bounded upstream tool IDs through response retirement.
- [x] R7: deadline native response and caller-final obligations.
- [x] R8: bound socket-to-session frame handoff outside PCM queues.
- [x] Additional lifecycle checks: owner loss in preparation, fixed-opening mismatch,
  output rejection/replacement, and stale audio credit.

Follow-up corrections:

- [x] Pin authorization context for the allocation lifetime; never treat local
  PCM serials as provider-consumption evidence or permit later origin reassignment.
- [x] Opt into allocation closure at hold, changed-epoch release, direct policy
  replacement and relevant snapshot boundaries before delayed caller evidence.
  Fence active sink playback before closing; keep repeated same-epoch release
  idempotent. Changed-context admission also fails before wire input.
- [x] Exclude microphone input during queued text/opening work and wait for native
  caller obligations before dispatch. Queued tool continuations keep admitting
  same-context PCM needed for endpointing and may proceed after caller final
  despite trailing PCM.
- [x] Require input transcription and exact audio/native-turn settings at readiness.

Final verification: 102 focused adapter/descriptor/capability tests pass,
including 19 scoped session cases and ten compiled room cases. Six additional
configuration/codec/auth cases and the local socket burst test pass. The direct
policy handler was moved into the existing Policy module to satisfy the 800-line
module bound; 73 affected room/capability tests pass after that refactor.
Registry/catalog, configured credentials and rendered browser evidence are in
the integration labnotes. Final Mini acceptance passed two native turns on one
connection in 11.1 seconds; Max passed one native turn in 6.3 seconds. Six actual
provider sessions were used (five Mini, one Max), including the earlier diagnostic
failures. No other provider or real telephony was used.

All six root gates pass on the final source: formatting, warnings-as-errors
compilation, strict Credo, full default tests (4,491 cases, zero failures,
159 excluded), unused dependency check and Lean (nine build jobs and one passing
oracle replay). The final local WebSocket burst test passes as well.

Independent GPT-6 Astra xhigh source review found no remaining actionable code or
test findings after the corrections and policy-module refactor. Final independent
review verified the completed gate evidence and current
documentation and gave clean sign-off: no remaining actionable code, test,
security, lifecycle or documentation findings in the reviewed scope.

## Checkpoint commits

All five checkpoints were implemented and verified before final independent
sign-off; this list tracks persistence of that reviewed work in dependency order.

- [x] Model configuration and private authentication.
- [x] Allocation-bound input cutover and acknowledged socket delivery.
- [x] Scoped native speech runtime and protocol/lifecycle regressions.
- [x] Provider registration, configured credentials, room acceptance and catalog UI.
- [x] Narrow live lane and final acceptance evidence.
