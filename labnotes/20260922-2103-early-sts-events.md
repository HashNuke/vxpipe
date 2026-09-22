# Early STS event acceptance gate

Baseline: `46322435`. The input-only context boundary is committed and its 74
focused checks pass on main. Four root static gates also pass; full umbrella tests
remain intentionally red at the five Google controller response-ownership cases.

## Design review before tests/runtime

Russell Astra xhigh reviewed the input checkpoint and found no input-boundary
defect, but the existing provider probe emits `input_submitted` before returning
`{:error, :busy}`. Channel can currently deliver/ack that event while the
context is only staged. A future `response_started` from that callback would be
more dangerous: it might be admitted even though input was rejected. Event
emission is synchronous, so Channel must acknowledge receipt promptly without
waiting for callback completion; consumer delivery is the operation to defer.

The first focused red will prove staged response-start and input-submitted events
do not reach the consumer before the exact callback result. On acceptance,
release them FIFO after the context commits. On rejection, never publish them;
if events emitted during the callback cannot safely be separated from older
asynchronous model evidence, fail the allocation rather than silently drop
unrelated evidence or grant authority from staging. Do not change legacy STS,
STT or TTS delivery. Keep bounded EventQueue behavior. Full response admission,
policy authorization and Google adoption remain separate milestone tasks.

## Red and green evidence

Added an optional probe-side early response-start emission and three actual
Channel tests: accepted response start, rejected response start, and accepted
early typed-input submission. The first owning-child run (`--seed 0`, two BEAM
schedulers) failed exactly those three cases, 16 tests / 3 failures: each event
arrived in the consumer mailbox while the input context remained staged.

Channel now records the event sequence at input reservation, holds opted-in
delivery while that input is pending, and disables terminal pre-delivery for that
case. An accepted result commits the context and then dispatches the queued
events. A rejected result with any newly emitted event fails the allocation
before delivery; rejection without such an event retains the normal rollback
and recoverable error. The existing early typed-input rejection test was
updated to assert this fail-closed behavior. `Event.emit` still returns promptly
inside the held provider callback.

The focused context file passes 17/0. The complete owning-child `speech/` group
passes 200 tests / 0 failures (3 excluded), seed 0, two schedulers. This does
not exercise Google response binding, channel grant or policy-qualified output.
Russell Astra xhigh follow-up found one uncovered ordering: after a clean
rejected first-use callback returns `:busy` with no early event, a later
`response_started` carrying its now-unknown context is still generically queued
and could be acknowledged. Added that finding to the milestone before repair.
The next red must reproduce delayed emission from the bound provider process,
then Channel must require an exact staged reservation or accepted context before
enqueue. No hosted call occurred.

Late-unknown red: 18 tests / 1 failure, provider `Event.emit` returned `:ok`
after context rollback. The guarded `accept_event` now rejects unknown and
mismatched staged contexts; focused 19/0 and full speech group 202/0. A further
accepted-prior-context test passes (focused 20/0). Russell's second source review
found a distinct case: A's accepted-origin `response_started` during staged B
is held correctly, but B's clean rejection incorrectly fails the allocation
because the rejection check looks only at event-sequence change. The milestone
records an exact-origin distinction before this next red. The full umbrella
baseline was stopped at the user's request; it was unnecessary for TDD red proof
and its partial output is not a completion gate.

The A/B focused red was 21 tests / 1 failure: B returned `:session_failed`
instead of preserving its recoverable `:busy` and A's queued response evidence.
Channel now tracks whether the pending input emitted *unsafe* semantics.
`response_started` naming a different already-accepted origin is safe to keep;
same-origin/staged or unattributable events remain fail-closed on rejection.
The focused file passes 21/0. The full owning-child `speech/` group passes
204 tests / 0 failures (3 excluded), seed 0, two schedulers. No umbrella suite
was used as a TDD red proof.

Russell Astra xhigh's final read-only source review cleared the scoped gate
after both late-unknown and A/B-origin repairs. It did not independently rerun
tests. Output admission, provider response indexing and Google integration are
not part of this checkpoint.

## Post-commit static finding

At committed `def93139`, root format, warnings-as-errors compile and unused
dependency checks pass. `mix credo --strict` fails: `Speech.Channel` is 861 lines
against the 800-line rule, and its input-result branch nests to depth 5. These
are project-owned consequences of the gate edit. Recorded a separate milestone
task before refactoring: extract cohesive event delivery/context logic and
flatten settlement, with focused regression and four static gates. No full
umbrella test rerun while the five known Google controller reds remain open.

The refactor moved gated dispatch, terminal pre-delivery, exact context checks
and prior-origin classification into cohesive `Speech.EventDelivery`, leaving
Channel at 791 lines. The input-result continuation is a small flat helper.
Owning-child `speech/` regression stays green at 204/0 (3 excluded), seed 0,
two schedulers. Post-repair root static checks are pending; no full umbrella
test was started for this red/green cycle.

Russell Astra xhigh cleared the extraction by read-only source review: moved
FIFO/early classification remains equivalent and the settlement helper keeps
deadline, reply and dispatch order. It did not rerun tests or static gates.
