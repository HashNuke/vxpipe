# Usage, cost observations, and billing enrichment

Status: in progress. Typed observation/settlement plus successful, failed, or cancelled model and
text-to-speech attempt capture into the private archive are implemented (2026-09-11); speech-to-text,
tool/carrier boundaries, operator totals, and billing enrichment remain. Specification review:
approved (2026-09-08).
Prerequisites: [Asynchronous history](asynchronous-call-history.md); [Remote MCP](remote-mcp-tools.md); [Telnyx](telnyx-calls.md); [Twilio](twilio-calls.md).
Sources: [Usage contracts](../../labnotes/20260905-0405-call-definition-design.md#usage-observations-and-call-participant-and-turn-attribution--approved-r44r46); [R44–R46](../call-definition-gap-review.md).

## Runnable outcome

An operator inspects each call's model requests, speech-service intervals, tool/carrier operations and available costs. Missing prices remain unknown, while tokens, text characters, audio durations and real provider request/session IDs remain useful.

## Specification

- Extend model/STT/TTS and applicable tool/carrier boundaries to emit typed usage observations even for intermediate model tool rounds and failed/interrupted operations. Preserve normalized responses without discarding usage; suppressing stale speech must not discard incurred usage.
- Every observation is call-scoped. Add participant/activation/service-active interval/leg/turn only where evidence supports it. STT/TTS can span multiple intervals; do not equate participant presence with billing duration or divide shared costs evenly across turns. One fact with multiple dimensions is charged once per aggregate.
- Save real provider operation/request/session IDs with integration/tenant namespace, never substitute local IDs as provider IDs. For TTS observe input-text characters and generated audio duration; for STT audio duration and recognized-text characters when available/permitted. Document measurement units; do not duplicate interim/cumulative text or retain denied text merely to count it.
- Retain observations and derive effective attempt/component amounts: deltas add, cumulative totals replace, final supersedes estimates, explicit corrections may decrease/increase, stale estimates cannot replace finals. Deduplicate proven delivery identities, not equal values; keep included subcategories separate from aggregate totals.
- Monetary values are exact decimal with currency/source/status; unavailable price/usage is
  not zero. Keep provider-reported price separate from library/catalog-derived estimates;
  inspect agent-runtime/ReqLLM provenance rather than relabeling best-effort cost as a provider
  bill. No new local pricing catalog.
- Optional configured billing lookup can enrich by real provider ID only where an API supports it. Run outside live room via existing tenant credentials, preserve original observations, never reset ended_at/retention or recreate purged data. A fake adapter proves workflow; actual supported billing integrations need their own verified API evidence.

Delta/cumulative mode is independent from estimate/final/correction status; finality does
not turn a delta into a replacement total. Use source sequence/provenance for stale reports,
not blind arrival order. Accounting must not start prohibited STT to obtain missing usage.

## Implementation checklist

- [x] Red-test typed adapter usage, attribution and observation arithmetic before modifying provider result contracts.
- [ ] Capture supported usage in buffered/streaming model and hosted speech adapters plus tool/carrier boundaries.
- [ ] Persist private observations/effective projections asynchronously and expose tenant-safe operator totals by meaningful dimension/currency.
- [ ] Implement optional billing-enrichment port/workflow with a controlled provider fixture and honest unavailable support.
- [ ] Verify measurement/provenance semantics and document supported provider billing lookup capabilities.

## Acceptance and failure checks

- [ ] Deltas 100 + 60 = 160; cumulative 100 then 160 = 160; cumulative 1000/1600/final 1700 = 1700; explicit 1650 correction wins over stale 1800 estimate.
- [ ] Two distinct 50 deltas total 100; proven duplicate delivery does not add; included token categories are not counted twice.
- [ ] Multi-round model and multi-segment TTS retain separate attempts; interrupted/failed usage survives stale-output filtering.
- [ ] STT interval/characters are observed without invented turn cost; unknown IDs/price stay absent; units/currencies do not mix.
- [ ] Later billing can complete after room end without blocking it, violating source privacy, or reviving a purged call.
- [ ] Finalized non-overlapping deltas 100 + 60 remain 160, not 60; a stale cumulative observation
  cannot regress the effective amount solely by arriving later without correction evidence.

## Manual verification

1. Run a call with several model tool rounds, speech intervals, a transfer, and interrupted TTS.
2. Inspect private observations and dimensioned totals; compare provider IDs and measured units with controlled fixture evidence.
3. Deliver duplicate/cumulative/corrected observations and verify effective totals.
4. Finish a fake delayed billing lookup after call end; inspect enrichment while unchanged ended_at and retention remain.

## Scope boundaries

No made-up prices/usage, per-turn forced allocation, floating-point billing records, automatic price scraping/catalog, universal request-level billing guarantee, or new synchronous live persistence.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (2026-09-11, typed observation and settlement checkpoint):

- Added Call Engine-owned value objects for optional evidence-backed attribution, provider
  namespace and genuine external identifiers, exact component measurements, immutable
  call-scoped observations, and derived effective amounts. Provider request/operation/session IDs
  remain explicitly available but are excluded from ordinary struct inspection.
- Added deterministic settlement for additive deltas, explicitly sequenced cumulative reports,
  estimate/final/correction precedence, stable observation/delivery/source-sequence replay
  detection, aggregate/subcategory inclusion, and provenance-specific totals. Monetary values use
  `Decimal`; floats are rejected and a cross-provenance total is rejected as ambiguous unless its
  provenance is selected.
- Red evidence: `mix test test/vxpipe/call_engine/usage/settlement_test.exs --max-cases 1`
  initially produced five expected undefined-module failures. The expanded provenance and replay
  cases subsequently produced two expected failures before their implementation.
- Green evidence: the same focused command passes 6 tests. The owning Call Engine suite passes 363
  tests with one existing integration exclusion. All root gates pass: formatting, warnings-as-errors
  compilation, strict Credo over 671 source files, all 851 tests across the eight umbrella apps,
  and the unused-dependency check.

That first checkpoint was partial: no provider adapter emitted the contract and it claimed no
persistence, inspection, or billing-lookup behavior.

Implementation evidence (2026-09-11, completed model-round capture checkpoint):

- Model responses already carried bounded usage and redacted call metadata from Agent Runtime.
  Call Engine now translates supported input/output/total token evidence for every successful
  intermediate or final model round into separate provider-neutral observations. Each round has a
  distinct local attempt ID; genuine provider request/response/session IDs remain explicitly
  namespaced and are never synthesized from that local ID.
- A request-scoped round tracker remains until Agent Runtime's terminal event, so task-result and
  event messages arriving from different processes cannot discard an already emitted usage event.
  The projection whitelists supported fields, derives no missing measurement, ignores arbitrary
  metadata, and does not persist a cost field until its provider-reported versus library-estimate
  provenance can be proven.
- `RoomAuthority` accepts usage only from its current activation or a source activation awaiting
  committed-transfer teardown, validates the pinned tenant/call/room/incarnation and participant
  activation, and hands explicit JSON facts to the existing bounded private archive/live-inspection
  port. There is no client event. A provider operation may be retained with no measurement, leaving
  totals unknown rather than zero.
- Red evidence: the measurement-less-operation test first failed with
  `{:error, :invalid_observation}`; the pure projector first failed because the module was absent;
  the coordinator test first failed on missing usage configuration; and the room test crashed on
  the deliberately absent `RoomAuthority` message clause, then timed out waiting for
  `usage_observed`.
- Focused green evidence: 7 settlement tests, 2 projector tests, 20 coordinator tests, the
  definition-driven room/archive case, and 5 activation-supervisor tests pass. The complete Call
  Engine suite passes 369 tests with one existing integration exclusion. All root gates pass:
  formatting, warnings-as-errors compilation, strict Credo over 676 source files, all 857 tests
  across the eight umbrella apps, and the unused-dependency check.

This remained a partial checkpoint. At that point, hosted speech, tool and carrier capture,
failed/interrupted model attempts, persisted settlement/operator totals, and billing enrichment
were not claimed.

Implementation evidence (2026-09-11, model-attempt lifecycle checkpoint):

- Agent Runtime now emits an attempt-start event immediately before each actual provider call and a
  completion event even when a valid model response has no supported usage or provider metadata.
  Pending-context/model-context failures therefore do not invent provider attempts.
- Call Engine opens a fresh attempt on that start event. A usage event closes it as succeeded; a
  terminal failure or cancellation closes an otherwise-open attempt with no measurement. Unknown
  usage remains unknown, while the fact that provider work began survives cancellation. Retries
  receive fresh attempt IDs even when their command/correlation is reused.
- A valid streaming-provider response still hands off its usage when a local output/event budget
  rejects the response. The request reports the local failure and publishes no rejected text, but
  known incurred usage is not discarded.
- Red evidence: both Agent Runtime usage tests first timed out waiting for the absent start event;
  the Call Engine coordinator tests then timed out waiting for failed and cancelled observations;
  and the streaming-budget test timed out waiting for known usage from its rejected response.
- Focused green evidence: 2 Agent Runtime usage tests, the streaming-budget case, and 22 coordinator
  tests pass. The complete Agent Runtime suite passes 59 tests with two integration exclusions, and
  the complete Call Engine suite passes 371 tests with one integration exclusion. All root gates
  pass: formatting, warnings-as-errors compilation, strict Credo over 676 source files, all 860
  tests across the eight umbrella apps, and the unused-dependency check.

At that point the milestone remained partial: hosted speech, tool and carrier capture, persisted
settlement/operator totals, and billing enrichment were not claimed.

Implementation evidence (2026-09-11, text-to-speech attempt checkpoint):

- Definition-selected synthesis runtimes now pin a safe provider/profile identity alongside call,
  participant, and activation identity. Provider adapters expose only their stable name and model;
  credentials remain in the existing inspected-redacted provider/transport configuration. The
  legacy room-command path has no pinned call/profile evidence and emits no usage rather than
  manufacturing that identity.
- A synthesis attempt starts only when `Speak` is transport-accepted. Rejected `Speak` and queued
  requests create no attempt; accepted `Speak` followed by failed `Flush` retains a failed input
  measurement. Successful, interrupted, provider-failed, transport-failed, and downstream-output
  failure paths settle at most once, so already completed provider work is not rewritten by later
  playout failure.
- The attempt retains locally measured Unicode-grapheme input characters. It accumulates decoded
  provider PCM, including post-interruption discarded audio, and uses `Membrane.RawAudio` frame/time
  conversion to record generated milliseconds rather than playout progress. Validated request and
  speech IDs become genuine provider request/operation IDs; the local `tatt_` ID remains separate.
- Room authority authenticates the exact active TTS capability or exact prepared private-briefing
  capability and matches its participant/optional activation before handing explicit facts to the
  existing private asynchronous archive. No raw synthesis text or client-visible usage event is
  introduced.
- Red evidence: the attempt tests first failed with three expected undefined-module errors; the
  capability tests then timed out waiting for successful, cancelled, and failed usage events; the
  room/runtime tests failed on an absent pinned runtime identity and no archived TTS facts; and the
  transport-boundary tests first returned `:ok` instead of the expected rejected command outcomes.
- Focused green evidence: 3 attempt tests, 9 capability tests, the runtime contract, definition-
  driven private archive cases, and a private human-briefing archive case pass. The complete Call
  Engine suite passes 377 tests with one integration exclusion. All root gates pass: formatting,
  warnings-as-errors compilation, strict Credo over 679 source files, all 866 tests across the eight
  umbrella apps, and the unused-dependency check.

This remains a partial milestone. Speech-to-text, tool and carrier capture, persisted
settlement/operator totals, and billing enrichment are not claimed yet.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added final delta vs cumulative arithmetic, stale provenance handling and no prohibited STT for accounting; re-review approved.
The independent review is specification evidence; the implemented checkpoints and their runtime
verification are recorded above.
