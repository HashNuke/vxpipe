# Usage, cost observations, and billing enrichment

Status: in progress. Typed observation and settlement contract implemented (2026-09-11);
provider capture, archival/operator projection, and billing enrichment remain. Specification
review: approved (2026-09-08).
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

This is a partial milestone. No provider adapter emits the contract yet, and no persistence,
inspection, or billing-lookup behavior is claimed by this checkpoint.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added final delta vs cumulative arithmetic, stale provenance handling and no prohibited STT for accounting; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
