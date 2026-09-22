# Google STS output bounds

## Baseline and task

Previous goal turn made progress: agent-output public identity checkpoint
`6f5bb3f8` and follow-up evidence/tasks `84690312` are committed. The tree was
clean when this turn started. The same post-commit umbrella run remains live;
Call Engine passes 1,040 tests and Gateway is running. No restart on observation
timeouts. Earlier Gateway handoff failures remain separately tracked.

Read-only inspection confirmed that `Google.STSOutput.buffer_audio/2` bounds its
pre-admission list at 16 chunks but appends to an active output without checking
the limit. Record the concrete red/green, integration and verification tasks
in checkpoint E before implementation. Reuse the existing pending-chunk limit;
leave wire PCM validation and the shared single audio credit intact. Overflow
must fail the owned session honestly, without dropped speech, fallback or replay.

Work directly, with synthetic local protocol fixtures only. Google remains
unadvertised and hosted acceptance still requires explicit authorization.

## Reproduction and repair

Inspection of the existing wire chunk limit also found a second defect:
`split_audio/1` used a fixed-size binary comprehension and silently discarded
the tail of a PCM part larger than 131,072 bytes. Added a separate milestone
task before its regression or implementation.

- Pure buffer/codec group: **11 tests, three expected failures**. An admitted
  queue accepts a seventeenth pending chunk; moving a full pre-admission buffer
  into output admits more data; a 131,076-byte PCM part loses its last four bytes.
- Added real fake-socket/session/channel checks: withhold the first audio credit,
  fill all 16 pending slots, then deliver one more chunk. Before the repair,
  the provider never terminates. The corrected two-test regression yields one
  expected failure; the acknowledgement/FIFO case already passes. An initial
  test-only field typo (`pcm` instead of `Audio.payload`) was corrected before
  treating that run as behavioral red evidence.
- Apply the same 16-pending-chunk limit to active output. The existing failure
  path retires provider, transport and allocation; the integration check monitors
  all three and forbids replacement/replay. The channel still owns the one
  outstanding credit separately from the bounded pending queue.
- Split PCM recursively at the unchanged even chunk limit, preserving the final
  partial chunk. No wire size, format, model, deadline or credential change.
- **43 tests pass**, seed 0: Google `sts`, `sts_output`, `sts_session` plus shared
  `sts_conformance` and `sts_output` suites. FIFO tests fill the queue, acknowledge
  one item, refill the freed slot, and drain every item in order through normal
  generation completion and output settlement.

The prior identity umbrella run completed with all five gates passing (2,199
tests, zero failures, 42 excluded; seed 0). This is not evidence for these later
Google edits: they began after its Call Engine suite finished. Review and commit
this checkpoint before its own broader gates. The older intermittent native
handoff findings and all milestone lifecycle/hosted acceptance tasks remain open.

Documentation inspection also found the author guide still saying transport
microphone input was unconnected. Added a task first, then corrected that status
to distinguish the proven embedded calls/native input checks from the remaining
full native conversation, caller-turn and lifecycle gates. Documented the Google
queue limit and lossless PCM splitting without claiming hosted compatibility.

## Post-commit umbrella verification

Checkpoint `3b1fa264` was committed before starting its broader gates. The same
run was polled to completion without restart and exited successfully:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- `PGHOST=/var/run/postgresql mix test --seed 0`: **2,205 tests, zero failures,
  42 excluded**, including 1,046 Call Engine and 492 Gateway tests.
- `mix deps.unlock --check-unused`

This is local regression evidence for the buffer/tail checkpoint, not hosted
Google verification or a repair of the separately tracked intermittent handoff
failures. The provider-contract documentation follow-up records this completed
run without restarting it for documentation-only changes.
