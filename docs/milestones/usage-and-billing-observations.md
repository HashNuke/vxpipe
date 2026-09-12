# Usage, cost observations, and billing enrichment

Status: in progress. Typed observation/settlement, model/text-to-speech/speech-to-text/tool/carrier
capture, asynchronous structured persistence, tenant-safe report API, and operator call-inspection
presentation are implemented (2026-09-12); billing enrichment remains. Specification review:
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
- [x] Capture supported usage in buffered/streaming model and hosted speech adapters plus tool/carrier boundaries.
- [x] Persist private observations/effective projections asynchronously and expose a tenant-safe
  Calls report API with totals by meaningful dimension/currency.
- [x] Present the tenant-safe report through existing operator call inspection without exposing it
  to ordinary call clients.
- [ ] Implement optional billing-enrichment port/workflow with a controlled provider fixture and honest unavailable support.
- [ ] Verify measurement/provenance semantics and document supported provider billing lookup capabilities.

## Acceptance and failure checks

- [x] Deltas 100 + 60 = 160; cumulative 100 then 160 = 160; cumulative 1000/1600/final 1700 = 1700; explicit 1650 correction wins over stale 1800 estimate.
- [x] Two distinct 50 deltas total 100; proven duplicate delivery does not add; included token categories are not counted twice.
- [x] Multi-round model and multi-segment TTS retain separate attempts; interrupted/failed usage survives stale-output filtering.
- [x] STT interval/characters are observed without invented turn cost; unknown IDs/price stay absent; units/currencies do not mix.
- [ ] Later billing can complete after room end without blocking it, violating source privacy, or reviving a purged call.
- [x] Finalized non-overlapping deltas 100 + 60 remain 160, not 60; a stale cumulative observation
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

At that point the milestone remained partial: speech-to-text, tool and carrier capture, persisted
settlement/operator totals, and billing enrichment were not claimed.

Implementation evidence (2026-09-11, speech-to-text session checkpoint):

- Definition-selected recognition runtimes now pin call, participant/optional activation,
  configured profile, and provider-owned safe identity. Credentials remain inside the provider and
  transport configuration. The legacy application-configured room path lacks the call/profile
  evidence and remains unobserved rather than receiving guessed attribution.
- Every concrete provider transport receives a distinct local attempt and service-interval ID. A
  transport-accepted audio submission or normalized provider activity creates an observable start;
  policy replacement closes the old interval as cancelled, and provider/transport failure closes it
  as failed. A replacement transport receives fresh identities. Connected-only evidence can be
  buffered until later bound activity or terminal publication so early setup cannot evade the room's
  exact-capability authorization.
- Only a final provider turn emits measurement deltas. Flux final audio-window differences are
  normalized to integer milliseconds and recorded as provider-reported recognized audio duration.
  Final recognized text is counted as Unicode graphemes only while transcript storage is permitted.
  Interim/cumulative text, eager/resumed states, and repeated final turn indices add nothing, and no
  transcript text is retained by the usage tracker. Providers without a final audio window leave that
  measurement absent.
- Session lifecycle, measurement projection, and capability integration remain separate focused
  modules. Room authority accepts observations only from the exact STT process bound to the source
  participant connection and rechecks all pinned call identities before using the existing private
  asynchronous archive/live-inspection path. No client event or fabricated domain-turn/provider ID
  is added.
- Red evidence: provider decoding first failed on the absent normalized duration field; pure session
  tests failed on the absent projector; capability tests then timed out on final, policy-rotation,
  denied-transcript, and failed-session observations. The accepted-audio/no-provider-signal case
  separately failed until transport acceptance became provider-work evidence. Interval-boundary
  assertions then failed until start and terminal observations were added.
- Focused green evidence: 3 session tests, 7 capability tests, 6 hosted-provider adapter tests, the
  pinned runtime contract, and the definition-driven private archive path pass. The complete Call
  Engine suite passes 385 tests with one existing integration exclusion. All root gates pass:
  formatting, warnings-as-errors compilation, strict Credo over 682 source files, all 874 tests
  across the eight umbrella apps, and the unused-dependency check.

At that point the milestone remained partial: tool and carrier capture, persisted
settlement/operator totals, and billing enrichment were not claimed yet.

Implementation evidence (2026-09-12, tool-invocation checkpoint):

- Each invocation accepted by an activation's supervised tool registry now receives one distinct
  local `tlatt_` attempt identity. Its start observation counts exactly one locally measured
  `invocations` request; a duplicate submission with the same invocation identity/fingerprint
  reuses the existing work and emits no second observation.
- Terminal observations preserve the actual worker outcome as succeeded, failed, or unknown. A
  bounded timeout remains unknown rather than being rewritten as a failure or retried. Ordinary
  conversational interruption still does not cancel a tool worker, so accounting follows the
  invocation's eventual outcome instead of the interrupted output turn.
- The tool binding supplies only a safe namespace: host actions use `host_application`, engine
  platform/transfer/Call Variables actions use `vxpipe`, and remote tools use `remote_mcp` plus
  their pinned configured integration ID. No arbitrary remote result metadata is interpreted as
  provider usage, and no provider request/session ID is manufactured.
- Usage observations contain no arguments or results. Existing private tool history retains those
  payloads under its own visibility/storage contract; the usage facts correlate by tool-call ID,
  participant activation, and source turn. Room authority reuses its exact active/teardown agent
  source check and emits no client usage event.
- Red evidence: the pure attempt test first failed on the absent `ToolAttempt` module; terminal and
  remote namespace cases then failed on the absent terminal API and binding metadata; registry
  integration failed configuration on the absent usage contract. An archive assertion also caught
  and corrected an inaccurate test expectation that a host-provided action was engine-provided.
- Focused green evidence: 3 pure attempt tests plus 2 registry lifecycle cases pass; the relevant
  binding, activation, conversation, and private archive checks pass. The complete Call Engine
  suite passes 390 tests with one existing integration exclusion. All root gates pass: formatting,
  warnings-as-errors compilation, strict Credo over 685 source files, all 879 tests across the
  eight umbrella apps, and the unused-dependency check.

Implementation evidence (2026-09-12, carrier-leg capture checkpoint):

- Added one provider-neutral carrier attempt contract. It records one locally observed
  `carrier_legs` request only after local validation/media admission succeeds and immediately before
  the answer or dial adapter is called. A local leg ID identifies the Vxpipe attempt and attribution;
  it is never substituted for an external identifier.
- Accepted carrier identity adds the real provider leg as `operation_id` and the real provider
  session when present. The first valid answer or media-start event marks connection. A later valid
  end derives `connection_duration` only from non-regressing evidence; two provider timestamps yield
  provider-reported provenance, while receipt/local clocks remain locally measured. A later provider
  answer can improve an earlier local media-start boundary without emitting a duplicate state fact.
- Rejected dials/answers retain a failed terminal observation without duration or invented provider
  identity. Local cancellation and ambiguous submission cleanup retain cancelled/unknown outcomes
  without claiming a carrier end time. Duplicate connected/end handling is idempotent, and a
  mismatched event cannot mutate usage state.
- Gateway separates lifecycle adaptation, event-evidence translation, and a failure-isolated
  reporting port. Call Engine separately owns attempt state transitions and immutable observation
  projection. Telnyx and Twilio use these same provider-neutral boundaries. The default reporter
  routes exact tenant/call/room/incarnation/participant/leg observations to the existing private
  asynchronous archive; no client event or synchronous SQL write is added.
- Red evidence: the pure attempt tests first failed on the absent module; local-cancellation evidence
  then failed until unavailable duration was explicit; later provider timing failed to improve a
  local connected boundary; outgoing and incoming lifecycle tests timed out on absent reporting;
  rejected dial behavior returned success before the controlled adapter supported rejection; and a
  mismatched ended event initially emitted a false duration before validation was moved ahead of
  accounting.
- Focused green evidence: five pure attempt cases, private-room archive routing, thirteen outgoing
  lifecycle cases, six incoming lifecycle cases, three incoming activation cases, and the Telnyx and
  Twilio decoder suites pass. The complete Gateway suite passes 227 tests with six existing
  integration exclusions. Root formatting, warnings-as-errors compilation, strict Credo over 691
  source files, all 888 tests across eight apps, and the unused-dependency check pass.

This remains a partial milestone. Persisted effective projections/operator totals and billing
enrichment are not claimed yet.

Implementation evidence (2026-09-12, operator-projection contract checkpoint):

- Added a strict inverse for the private `usage_observed` call-fact representation. It restores the
  typed observation contract using fixed external-value mappings, rejects an attribution that does
  not match the fact envelope, and retains exact decimal currency values.
- Added one Calls-owned report contract for effective amounts and non-overlapping operator totals.
  Totals include root amounts only, group at every supported provider and attribution dimension,
  and keep unit/currency and provenance separate. External request/operation/session identifiers
  remain on individual effective amounts but do not fragment provider totals.
- Red evidence: the three focused contract cases failed on the deliberately absent projection and
  report modules. Green evidence: all three pass after the minimum typed decoder, value, and
  aggregation modules were added. Root formatting, warnings-as-errors compilation, strict Credo
  over 695 source files, all 891 tests across eight apps, and the unused-dependency check pass.

This is an enabling checkpoint only. No Ecto projection, inspection read, or operator presentation
is claimed yet.

Implementation evidence (2026-09-12, persisted usage-projection checkpoint):

- Extended the existing bounded `EctoStorage` path so a private usage fact is archived first and
  then projected into immutable structured observations. The room still observes only asynchronous
  handoff acceptance; SQL success or failure does not become room, media, model, tool, or carrier
  success.
- Added a Calls-owned usage repository port and report workflow. A `calls`-scoped principal can read
  only a call belonging to its tenant. The persistence adapter joins through the tenant and returns
  typed effective amounts; Calls derives the non-overlapping dimensioned totals.
- Added separate observation/amount schemas and focused record/value codecs. PostgreSQL numeric
  values restore scalar quantities as integers and currency as exact `Decimal` values. Private
  external provider identifiers remain on individual amounts and outside ordinary struct/schema
  inspection.
- Each observation transaction locks only its call, deduplicates exact replay, derives from the
  immutable observation set, and atomically replaces the rebuildable effective-amount projection.
  Included component facts may precede their aggregate: they stay inspectable but excluded from
  totals, preventing valid archive delivery order from becoming a retry deadlock.
- Red evidence: the persistence integration first failed on the absent public report workflow; the
  incremental-settlement case separately failed on the absent partial effective-amount API. During
  green iteration, immutable replay exposed an inaccurate millisecond-precision fixture and the
  first stable-ID attempt exposed reversed hash arguments; both were corrected at their owning
  boundary.
- Focused green evidence: eight settlement tests and two persistence projection tests pass. The
  complete Persistence suite passes 34 tests. All root gates pass: formatting,
  warnings-as-errors compilation, strict Credo over 703 source files, all 894 tests across eight
  umbrella apps, and the unused-dependency check.

This remains a partial milestone. The persisted report is not yet shown in operator call inspection,
and no billing lookup is claimed.

Implementation evidence (2026-09-12, operator presentation checkpoint):

- Added a Console backend boundary for the tenant-authorized Calls usage report. The selected-call
  LiveView reads usage separately from persisted history, live evidence, and recordings, so an
  unavailable usage projection produces its own generic recovery state without hiding other call
  evidence or exposing an internal reason.
- Extended the existing call workbench with one compact usage ledger. Non-overlapping totals are
  immediately visible by capability, configured provider, evidence-backed attribution, exact
  quantity/currency, and provenance. Individual effective operations remain in a disclosure with
  local attempt/component, genuine external references when present, attribution, and settlement
  state. Empty, partial-aggregate, and unavailable states stay distinct.
- Kept presentation responsibilities separate: the LiveView coordinates reads, one component owns
  usage markup, and one formatter owns closed value labels and exact quantities. The reusable
  Gateway and ordinary call clients gain no usage route or event.
- Red evidence: two presentation cases first failed because the panel was absent; the backend
  contract first failed because `usage_report/3` was absent. A rendered accessibility audit then
  exposed keyboard-inaccessible horizontal regions, and focused tests failed before their named,
  focusable region contract was added.
- Focused green evidence: the boundary and presentation files pass 4 tests, and the complete
  Console child suite passes 83 tests. Rendered `agent-browser` checks at 1440x1000 and 390x844
  showed both exact totals, all three operation rows, no document-level horizontal overflow, and
  keyboard-local scrolling for each wide table. Separate rendered fixtures showed the empty and
  unavailable states with no tables or leaked internal reason while the rest of the call evidence
  remained present. The scoped accessibility audit reports zero violations; its only incomplete
  result is an indeterminate contrast check for horizontally clipped off-screen cells.
- All root gates pass: formatting, warnings-as-errors compilation, strict Credo over 705 source
  files, all 896 tests across eight umbrella applications, and the unused-dependency check.

This remains a partial milestone. Billing lookup and its supported-capability evidence remain.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added final delta vs cumulative arithmetic, stale provenance handling and no prohibited STT for accounting; re-review approved.
The independent review is specification evidence; the implemented checkpoints and their runtime
verification are recorded above.
