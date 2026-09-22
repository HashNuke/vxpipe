# Private handoff policy continuity

Status: parent technically reviewed and approved on 2026-09-22, before tests or
runtime implementation; implemented with focused authority, speech-policy and
native evidence. This is an ownership correction within the authorized handoff
repair, not new user-facing behavior. Final integration gates remain parent-owned;
a distinct later native attachment timeout remains tracked in the milestone.
Independent review identified incomplete pre-barrier stale-selection validation
and an ordinary-admit omission bypass. Focused authority and room regressions now
cover both repairs, including queued ready/private loss and staged-supervisor loss
followed by same-ID rejoin. A further real connection-loss variant now preserves
attempt-local recovery when the ready result precedes connection `DOWN` in the
room mailbox. See `labnotes/20260922-1820-private-connection-review.md` for its
controlled red and the integrated 118-test green.

## Evidence and existing contract

Before this amendment, private STT capability/ingress and Gateway room input/output
actors received a locally applied base snapshot. They entered the authority's
enforcer map only at candidate adoption. A preparation worker could miss multiple
membership revisions while blocked on another resource. The controlled native
case pauses that worker across a monitor's departure/rejoin: the private base is
revision 8, the room reaches 10, and refresh rejects `unexpected_policy_revision`.
Recovery audio replaces the expected listener wait tone.

This is the correct response of `Snapshot.validate_transition`: observing only
endpoints cannot establish intervening permission boundaries. It must not change.

The previous [readiness contract](readiness-resource-contract.md#adopting-newly-prepared-enforcers)
explicitly required local base application and prohibited ordinary private
registration because cancellation would become a critical room failure. The
[incremental policy contract](incremental-media-policy.md) requires retaining
unaffected prepared providers and distinct revoke/regrant intervals. The current
combination did not provide continuous policy delivery to staged actors.

`Authority.register_connection_enforcers/4` already supports local teardown of a
failed group. It is not sufficient unchanged: its group remains noncritical at
candidate adoption (`monitor_enforcer` preserves an existing registration), which
would change the destination's post-commit failure contract. Individual ordinary
registration instead makes pre-commit cancellation critical. Neither can simply
replace local application without a lifecycle decision.

## Approved decision

Add explicitly private, attempt-scoped registration using the authority's existing
enforcer map and acknowledgement barrier, not a second policy history or registry.

1. Authorized private allocation registers fresh actors before exposing their
   preparation receipt. The authority supplies their initial installed snapshot
   and every subsequent committed revision. Do not locally apply the same base
   and then register it again. The destination remains absent from membership;
   no registration grants input, output, transcript admission or readiness.
2. Registration pins the actual connection, phase owner, attempt and original
   absolute deadline supplied by the existing room authorization. Private actor
   loss/cancellation retires only its private group and triggers existing attempt
   cleanup; it does not make caller/source resources critical dependencies of
   the private actor. Uncertain teardown must still fail closed.
3. Keep STT capability/ingress and Gateway media ownership separately retireable,
   so removing speech demand does not cancel retained media. Existing phase and
   connection supervision remain responsible for actor teardown. Registration
   must not extend their lease or outlive cancellation.
4. The exact selected private actors become ordinary connection-owned critical
   enforcers atomically at validated candidate adoption, before applying that
   candidate. Required actor failure must not be treated as optional private
   retirement during commit. Reject stale/expired/foreign selection before this
   transition. Once application begins, retain existing fail-closed behavior.
   Selection includes retained dormant media from the private receipt, not only
   actors with required readiness descriptors. Admitting the destination while
   omitting its registered actors is rejected; partial group promotion is rejected.
   Removed STT demand is retired before selection, independently of retained media.
   Scoped receipts must still name matching private registrations: missing,
   explicitly retired and ordinary-registered actors cannot be substituted.
   Ordinary participant admission also rejects outstanding private registrations.
   The room checks its exact staged participant supervisor before entering the
   policy barrier. Authority also validates connection liveness at its own
   pre-barrier boundary, classifying dead scoped receipt ownership as private
   rejection. Proven pre-barrier private rejection recovers only the attempt;
   failure during or after promotion remains fail-closed.
5. Refresh validates current authority/candidate evidence instead of replaying a
   stale base snapshot from Gateway. Actual actors still process each revision
   through their unchanged strict transition and scoped interval logic. Existing
   preparation reconciliation retains unaffected generations and invalidates
   changed permissions; original media hold/release and cue fences remain.

This amends *when and with what failure classification* private actors register.
It does not amend permission rules, provider contracts, snapshot acceptance,
candidate authorization, or post-adoption failure semantics. Implementation needs
the narrow private-registration/adoption paths in MediaPolicy.Authority as well
as the already authorized private allocation/Gateway paths.

## Rejected alternatives

- Accept revision 10 over revision 8, compare only final permissions, or invent
  revision 9: all lose authoritative revoke/regrant evidence.
- Replace every private generation on a gap: cancels healthy prepared providers
  after unrelated membership changes, contrary to the retention contract, and
  adds avoidable startup to the unchanged deadline.
- Forward updates only when the preparation worker resumes: recreates the gap.
- Register ordinary critical enforcers early: private failure could close a
  healthy caller/source room before commit.
- Register existing noncritical groups without adoption promotion: silently
  weakens the committed destination failure boundary.
- Maintain/replay policy history: introduces a new ordering/retention protocol
  rather than using the existing authoritative barrier.

## Verification plan and design review

Before implementation, add failing owning-boundary tests for sequential delivery
while handoff work is paused; private owner/deadline/connection cancellation;
speech-only retirement; rejected registration; and exact critical promotion with
failure during/after candidate application. Prove no accepted revision is replayed
to survivors when a private group disappears.

Exercise unrelated revisions retaining the same provider, media actors and
deadline. Separately exercise permission revoke/regrant, requiring changed
affected generations/intervals and rejection of old buffered evidence. Candidate
readiness must be refreshed; no current or private evidence alone permits release.

Restore the controlled preparation-worker pause around the five-participant
case's later `departing_player` remove/rejoin. Baseline reproduction is recorded
in the prior handoff labnote; require native waiting and final bidirectional audio,
not merely a completed event. Repeat the bounded destination/participant loss
cases and private actor/phase cleanup checks using at most two schedulers.

Design review conclusion: continuous authoritative delivery best preserves both
strict policy ordering and unaffected-resource retention. Parent review approved
the explicit registration/adoption amendment and narrow authority/private actor
write scope. No permission/privacy/failure weakening, snapshot skipping/replay,
history, second registry, healthy-provider replacement or deadline extension is
authorized. Full umbrella acceptance remains parent-owned.
