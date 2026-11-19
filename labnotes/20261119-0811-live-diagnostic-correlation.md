# Live diagnostic correlation

A bounded Engine LiveReport now joins provider references, wrapper links, accepted
room IDs and response commands into revisioned per-turn timing records. It keeps
at most1,024 distinct packets and1MiB charged evidence/reports by default (caps4,096
and4MiB); saturation retires collection rather than evicting evidence silently.
Identifiers are detached before use as keys. Same-clock offsets use the run origin;
late acoustic confirmation revises the same room turn without moving the estimate
forward to confirmation time. Resumed or unmapped speech, resets, partial starts,
and ambiguous provider associations retain unavailable durations.

Provider cumulative samples are not source timestamps. Explicit normalized16kHz
provider/source sample anchors are required before acoustic timing can be available.
The bounded packet and worker forwarding exist, but actual adapter emission is not
yet implemented. Fixtures provide known mappings; this does not claim live profile
support. Missing mapping is clock_uncertain. Many-to-one provider associations omit
provider landmarks instead of combining stages from different provider turns.

Calls Collector receives only bounded evidence, uses the existing independent
writer, and persists live run/turn revisions. It has a16-source collector pool
(cap32),250ms revocation/loss checks and1s heartbeat. Closing stops capture, waits
at most2s for admitted writes, then persists terminal coverage and starts the
writer's separately bounded drain. Discarded revisions cannot yield complete
coverage. Collector death starts writer drain through its owner monitor; a crash
without final coverage leaves a running record that becomes unconfirmed. Known
reset gaps survive into run reasons without inventing a dropped-frame count.

Initial report tests failed5/5 for missing builder; three further correlation
regressions proved endpoint borrowing and identity ambiguity. Astra independently
proved retained backing-binary keys, late unmapped speech, ignored provider sample
coverage and duplicate canonical claims; all are retained and fixed. A second
review proved cross-provider stage fabrication, also retained/fixed. Builder final
review is clean (22tests plus1late-conflict probe). Worker mapping-forward test was
red before implementation.

Collector initial tests failed2/2 for missing collector; owner-monitor test failed
before its lifecycle fix, and pool admission test failed before the bounded API.
Astra reproduced lost-revision false completion, retained run backing binaries and
missing gap coverage. All three are retained and green after fixes. Current
focused Calls diagnostics32/0, Engine diagnostics135/0 and actual database
integration16/0 pass. Final collector review is clean (35tests including three independent lifecycle/race probes). Root static gates and Lean pass.

The real database test writes an incomplete row, adds late acoustic confirmation,
closes/drains the processes, and rereads the newer durable row plus terminal run.
It does not yet use a configured Scribe call. Application composition, acknowledged
provider profile, real sample-alignment production, bounded per-turn finalization
and configured-call on/off/isolation acceptance remain open. No live activation.

The background umbrella run finished with Google readiness and Telnyx fixture
identity races, independently reproduced and fixed in separate commits. A third
briefing_voice recovery750ms deadline failure could not be reproduced: isolated
and six instrumented runs passed; repeated recoveries296–325ms. No speculative
production change was made. The run also loaded a newly added persistence test
against the older CapturePacket already loaded in that VM, rejecting the new
mapping packet. It is mixed-source evidence, not final acceptance. Future root
acceptance must run against frozen source/build artifacts.

Final review reproduced the settlement-counter publication race with an OTP
debugger breakpoint: pending_count could reach zero before discarded was updated.
The collector now tracks explicitly acknowledged writes instead of inferring
settlement from that intermediate counter snapshot. A retained delayed-notification
regression failed before the fix; the debugger reproduction now verifies waiting
and incomplete final coverage. Two additional retained red/green tests cover
unmatched provider evidence and observed rows rejected by storage admission.
Unmatched counts mean retained landmarks lacking one unambiguous reportable
provider identity, including suppressed many-to-one associations; they are not
a count of raw provider wire messages. A frozen-source full umbrella rerun remains
required after this checkpoint.
