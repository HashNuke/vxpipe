# Shared tool settlement

## Scope

Continue the shared participant tool milestone after ownership checkpoint
`cff7f7f3` (committed and pushed). The milestone is 6/20 complete. Reuse existing
InvocationRegistry acknowledgement; do not add a second completion store or
change provider protocols in this checkpoint.

## Reproductions

Two compiled-room tests fail before implementation: the seventeenth sequential
native tool request is saturated because previous accepted results remain leased;
a provider that loses its association rejects a result, yet the room publishes
ToolCallCompleted and continues silently. The second test injects association loss
in the controlled Morse fixture after admission. Both failures reproduced before
changing production code.

The implementation acknowledges through the existing registry only after local
provider acceptance or an authorized terminal effect.
The completion bridge validates the exact leased ID before releasing its local
record. A provider rejection or acknowledgement failure terminates explicitly;
it does not retry the accepted business operation. Focused tests are green;
broader native regressions and independent review are in progress.

Interrupted associations still require the subsequent C3 work. This checkpoint
does not claim a trusted late-completion protocol or full conversation parity.

## Review reproductions

The initial 114-test regression lane passed (seed `431193`), but Astra identified
an untested transient scope mismatch: activity_turn can change without retiring
the allocation. A new compiled-room test reproduced unconditional acknowledgement
of an undelivered completion (seed `654411`). Pending associations now stay until
accepted settlement, so unresolved scope retains both association and lease.
The room acknowledges only after that removal, avoiding a second policy query
and its authorization race. Scope-denial unit assertions now verify retention
and continue to prohibit public/provider delivery. Late delivery/reconciliation
remains C3 work, so this is not a full completion-parity claim.

The suggested raw-caller-text diagnostic leak did not reproduce: a synthetic
caller-text sentinel was absent from the actual provider-rejection crash log,
including with expanded logger inspect options. No production diagnostic change
was made on that unconfirmed finding. No real caller data was inspected.

An ordering regression also reproduced a race in the previous checkpoint's
tools-first test: the fixture's original ready message could arrive after the
test deliberately reset its flag. The fixture now traces/observes that original
signal before replaying the opposite order; runtime readiness code is unchanged.

## Verification and review

Final native lifecycle/identity, ownership, transfer and common invocation-registry
lane: **115 tests, 0 failures**, seed `915194`. It includes 20 sequential accepted
native results, duplicate completion delivery, invalid lease acknowledgement,
controlled provider rejection, retained unresolved scope, concurrent saturation
and the existing registry's consumed-ID rejection. Formatting, warnings-as-errors
compilation, strict Credo and unused-dependency checks pass. Lean build, oracle
and replay pass (1 test, seed `512115`).

The complete root suite last passed at `cff7f7f3`: 5,129 tests, zero failures.
That result precedes this settlement change; this checkpoint's evidence is the
focused lane and quick root gates above. The next complete umbrella run remains
an integration/final acceptance gate for the unfinished milestone.

GPT-6 Astra xhigh re-reviewed the fixed source/tests and found no actionable
issues. The unconfirmed logging concern was withdrawn. The milestone remains
6/20: this is partial C3 progress, with interrupted delivery, terminal discard,
private-reference replay and conversation policy still pending. No deployment.
