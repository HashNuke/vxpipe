# Routed STT boundaries

## Scope and evidence

Verify real STT allocation replacement when external/hybrid audio-routing policy
changes, independently of the human participant/connection identity. Both local
Silero modes are exercised with configured Scribe and Morse providers.

The first attempt used native `TOOL transfer` to a fixture LLM. All four cases
failed in existing operational transfer handling before a replacement STT session.
Independent review traced pending half-duplex tools to unsafe hold and separately
external/hybrid stop to transfer-authority revalidation failure. Reproduction and
scope are recorded in [the deferred issue](issues/external-sts-tool-transfer-authority.md).
No operational/provider code was changed to make the diagnostics tests pass.

The retained cases admit/remove a pinned presence restriction with empty audio
routes while save_transcripts remains enabled. This exercises the real
SpeechToTextDemand activity-authority replacement path. Four cases pass: the old
observer exits, generation changes, fresh Scribe sessions acknowledge configuration,
the old run closes and the same human/connection produces a new run/canonical row.
This proves policy-routing boundaries, not successful native tool transfer.

Strengthened source-change reason, stale handoff/signal rejection, allocation IDs
and exact run-count assertions are under verification. Final independent review,
full focused configured selection and static gates remain pending.

## Closure provenance correction

The strengthened configured tests failed four times: source replacement closed the
run with `lease_expired`. A focused Collector assertion reproduced this (9 tests,
1 failure). CaptureHandoff now records the first observed closure cause, shared
between a worker's input and collector output but separate from their queue/open
state. SourceAttachment closes captures before cancelling its lease. Collector
uses the recorded cause rather than treating every closed handoff as expiry.

Review identified a kill-before-terminate race. A suspended-worker regression
failed (19 tests, 1 failure) before provenance sharing; it now sees the source cause
at the collector output before killing the worker. Explicit close after expired
settings separately failed (10 tests, 1 failure), then passed after retirement
checked the existing authority deadline. Original source/expiry causes survive
later cleanup in either order.

The stale signal assertion now establishes a real fresh canonical turn, matches its
reference/index/policy and current source intervals, and injects only the retired
allocation generation through the current capability. The turn must remain intact
until actual Scribe completion. Four configured cases pass with source-change
reasons, distinct allocation IDs and exactly two persisted runs. Focused Engine
diagnostics pass 231/231; Calls diagnostics pass 49/49. Review controls, final
configured selection and static/Lean checks are still running.

## Final review corrections

A generation-only positive control failed all four configured cases at the active
turn assertion: using the current generation actually consumed the turn. The
normal old-generation cases independently passed 4/4. This validates the stale
signal proof rather than relying on unrelated mismatched identity fields.

Review reproduced owner DOWN overwriting an already recorded lease expiry with
source_changed. Its deterministic suspended-collector probe failed 1/1; the probe
is retained and generic DOWN now respects the shared first cause. Calls diagnostics
pass 50/50 after this fix.

The full configured selection exposed a teardown race in its existing drain helper:
the worker supervisor disappeared between registry lookup and count_children.
The helper now retries only that noproc exit rather than failing or accepting an
unproven drain. Other errors retain their normal failure behavior. Final rerun and
review are pending. Root format, compile, strict Credo, unused-lock and Lean passed
before the final Collector DOWN fix; static checks are being repeated afterward.

Review also reproduced owner DOWN as the first observer of expired authority:
selecting the reason before closing capture still mislabeled expiry. DOWN now
closes capture first, then reads its immutable cause. Both expiry orderings are
retained; Calls diagnostics pass 51/51. The exact deferred native-transfer recipe
was independently run with synthetic providers and failed at ToolCallCompleted as
documented, with policy_changed and speech_to_speech_unavailable recovery evidence.

## Final parent verification

After all corrections, the complete configured diagnostic selection passes 21/21,
Calls diagnostics 51/51 and Engine diagnostics 231/231. Root format, compile with
warnings as errors, strict Credo and unused-lock checks pass on the final code.
Lean passes for the handoff/source-lifecycle change. Changed documentation links
resolve and git diff --check is clean. No live provider test, Telnyx change, full
umbrella suite or deployment occurred. The milestone eligibility/replacement task
is now checked; remaining lifecycle/continuity, UI and E/F gates stay open.

Final scoped Astra review is clean. Independent closure-race probes pass 2/2,
handoff/worker checks 29/29 and configured replacement cases 4/4. The generation-only
positive control fails 4/4 as expected. The exact deferred-issue recipe reproduces
the documented operational failure. Review made no repository edits.
