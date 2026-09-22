# STS egress revocation

Continue the independent audit's directional-policy reproduction after
`d47513b7`. Root format, warnings-as-errors compile, strict Credo and unused-lock
checks pass for that checkpoint. Its Call Engine child suite is running with
two schedulers; no new root/Gateway result is claimed. The Gateway agent owns
native handoff repairs; the load agent owns its timing-attribution review fix.

## Plan and design review

Expanded the existing milestone task before tests/code. Separate admitted
output fencing from authorization/retirement of future and queued output. Both
policy APIs currently inspect human-to-agent permission only; the denied-audio
branch then drops `active_output` without returning credit or terminal cleanup.
Use existing sink/provider fencing and zero-playback settlement, and preserve
human input that its independent direction still permits. Test generation and
drain explicitly using a controlled real speech channel, not timing sleeps.
Future/queued admission remains open until its own evidence is complete.

Red evidence: **33 tests, five failures**. Four controlled real-channel cases
retain caller-to-agent permission and revoke only agent-to-caller audio through
each policy API, during generation/drain; all lack sink interruption. A direct
output-consumer boundary case with a real credited session fails to return the
denied chunk's credit. Both cases require no second terminal event and prove
provider output-slot reuse after late generation completion. The initial fixture
run expected `:ok` for chunk submission; corrected that assertion to the real
`{:ok, credit_ref}` contract before recording behavioral red evidence.

Green: **33 tests, zero failures**, seed 0. Both update APIs now inspect both
audio directions before retaining an admitted output. The output-consumer
denial branch returns its valid credit and runs normal fencing/settlement.
Each real capability case verifies permitted microphone input, exactly one
interruption, discarded late PCM, zero-egress late completion, ignored old sink
completion and fresh output-slot admission after regrant. This evidence does
not close future/queued-reply retirement or native-call acceptance.

The joined capability, room identity/publication, startup and provider tool/
control pass is **140 tests, zero failures**, seed 0, two schedulers. Exact-file
formatting, whitespace checks and 46 local documentation links pass. The complete
1,102-test Call Engine run recorded in the preceding recognizer labnote passed
before these changes; it is not a full-suite claim for this checkpoint. Commit
before broader gates and preserve the pending native/Gateway integration window.

After commit `51926f76`, root format, warnings-as-errors compile, strict Credo
and unused-lock checks pass. Full umbrella/Gateway testing remains pending
integration of the independent handoff repair. No new root test pass is claimed.
