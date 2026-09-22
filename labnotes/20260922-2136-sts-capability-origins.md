# STS capability origins

Baseline `8e52be76`, after the reviewed shared response-start grant. The only
pre-existing dirty file is the five deliberate Google controller reds; preserve
it separately. Focused owning-child controller run on this baseline: 49 tests,
five expected failures, all at premature agent-turn admission immediately after
caller/text completion. No hosted call or full umbrella run was used for red
proof.

Read the milestone's response-ownership prerequisites, Google response design,
capability input/output, shared `Session` context options and Channel context
staging. The shared channel can now require a context, but the real capability
still sends legacy context-free input; Google still advertises no start event.
The next critical boundary is therefore an immutable pre-input capability
origin. Added three explicit dependency tasks to the milestone and a focused
origin decision to the design document before tests or runtime changes.

## Focused red/green and design decisions

From `apps/vxpipe_call_engine`, `ERL_FLAGS='+S 2:2' mix test
test/vxpipe/call_engine/capability/sts_capability_origins_test.exs --seed 0`
failed 1/1 on `{:error, :invalid_response_context}` for a real opted-in
capability audio call. `ResponseOrigins` now proposes an allocation/source/
epoch/bidirectional-policy fingerprint before the shared input slot, commits
only successful input and reuses unchanged context. Direct audio, typed text,
external activity and framed microphone input use the same submission path;
non-opted descriptors still pass no context. The first focused green was 1/0.

Added focused cases for rejected first-use rollback, snapshot output-route
revoke/regrant, the interim 16-context cap, and framed ingress epochs. A fifth
case reproduced a direct `apply_policy` update after a Snapshot: it failed 1/5
because the snapshot intervals remained unchanged and an old context was
reused. An origin-only direct-policy revision in the fingerprint fixed that
case; the focused suite then passed 5/0. The framed test raised it to 6/0.
The relevant capability and speech group passes 255 tests, zero failures,
three integration tests excluded, seed 0. No hosted call or full umbrella test
was used for TDD red proof.

This checkpoint does not bind Google's unlabelled wire content to a context,
authorize a queued response at grant, retire response/tool origin holds, or
complete the five red Google controller cases. Those remain milestone tasks.
Post-commit static gates are pending.

Independent Astra xhigh source review identified two concrete flaws. The
output interval used the agent's incoming scope, not the human recipient's
incoming scope; an output-only revoke/regrant with unchanged caller outgoing
set would reuse the old context. Held direct activity could also fall back to
the allocation generation and accept new input after `hold`. Both were added
to the milestone before implementation. Focused tests reproduced 8/2; using
the human output interval and an explicit opted-in held guard made them 8/0.
The capability/speech group then passed 257/0 (three integration exclusions).
Independent Astra xhigh source follow-up found no remaining actionable issue
in this scope; it did not rerun tests. Google wire association, grant-time
policy and exact origin retirement remain open.
