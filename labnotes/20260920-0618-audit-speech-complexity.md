# Audit speech complexity

The user accepts implementing the complete admission/cancellation workflow together
and asks to reduce duplicate state and rely more on OTP. They specifically prefer
simple topology over complex recovery. The milestone goal remains paused after the
previously proved early-admission cancellation regression; this turn audits and
updates the proposal without modifying runtime code.

## Findings

Read the speech subtree, native Morse TTS, existing capability/usage accumulation,
ownership/semantic contracts, milestone and preceding failure evidence. Output
performs bounded credit/playback bookkeeping, not sink or provider I/O. Channel
coordinates the same request through synchronous Output calls and another copy of
request lifecycle state. Merge that state under Channel, retaining pure helpers
where cohesive and keeping blocking provider calls in Input. This deletes a
process boundary and its handoffs rather than just reorganizing modules.

Source searches confirm unread `Output.last`, Channel `request.handle` and Channel
`request.submitted?`; Output's accumulated `generated_bytes` currently has no
consumer. Remove unread copies during the refactor, but preserve required usage
facts. Channel's last successful cancellation is read for idempotence and stays.

The only runtime `SessionTree.commands/1` caller starts initialization from
Admission. A temporary initializer Task under the existing local DynamicSupervisor
is a later candidate to remove the otherwise idle Task.Supervisor. It must start
after binding, return promptly, retain public-only child arguments and preserve
startup deadlines. This is not a reason to run blocking work in shared Admission.

Manual provider retirement appears in Session, Channel and ScopeControl. Deleting
it indiscriminately is unsafe: the provider can hold its supervisor during init,
and the registration gate prevents a cancelled pre-bind child escaping. The
current temporary significant children already give allocation-wide shutdown.
Keep external authority monitors and provider-loss detection unless the chosen
tree demonstrably replaces their obligations. Do not add a reaper/retry process.

The earlier custom atomics receipt was a proposed representation, not implemented
behavior. Withdraw that choice and first red-test immutable bounded fact delivery
to an existing independently owned consumer/usage owner. Existing usage helpers
are calculation logic, not evidence of failure survival. Publish facts before
acknowledging their acceptance to the provider and collect through Channel DOWN;
live media ACK revocation cannot discard historical incurred-work facts. Retain
metadata bounds, provenance and the distinction between uncertainty and zero usage.

## Verification and independent review

Consulted official Elixir GenServer and Supervisor documentation and Erlang
supervision principles. They support processes for runtime isolation, significant
temporary children for automatic shutdown, and the need to keep blocking callback
and initialization work away from control/shared startup. No dependency changes.

Reused the user-authorized GPT-6 Astra xhigh reviewer for a read-only audit. It
independently confirmed the Output merge, dead state, initializer candidate and
startup protections, and required a real historical accounting delivery contract.
It made no edits and ran no BEAM work.

Reran the existing isolated paired diagnostic from the owning child:

```sh
mix test test/vxpipe/call_engine/speech/tts_admission_cancellation_test.exs --seed 530504
```

Result: **2 tests, 1 failure, 0.8 seconds**. Input-first control passes. Pending
Input cancellation returns busy after fencing; Input then clears, the fence
expires, descendants terminate and replacement returns closed. This confirms the
existing pause reason; none of the simplification candidates is presented as a
newly tested failure or an implemented fix. Prior green load/root results do not
certify current early-admission source.

Created `labnotes/20260920-0041-speech-complexity-audit.md`, revised D2/D4 and the separate design
review in the milestone, linked the audit from the index, and marked the receipt
representation in the admission report as superseded. R/A remain accepted (2/9);
no implementation checkbox was advanced. D becomes one complete tested workflow,
with internal red/green steps and later independently verified startup cleanup.

No runtime changes, full root gates or load diagnostic were needed for this
documentation-only audit. The future merge still requires focused regressions,
failure evidence, serial load, independent review and all five root gates. The
existing uncommitted D work is preserved; no D implementation commit or rollback.

Final Astra documentation review found the revised direction clear. Applied its
precision correction: the historical usage consumer must survive the whole speech
scope, not merely one allocation. Explicit publication-before-provider-ACK and
collection-through-Channel-DOWN requirements are in the audit. Reviewed the changed
documentation and verified local link targets and whitespace; no acceptance status
advanced and no claim of a measured benefit from the proposed merge was added.
