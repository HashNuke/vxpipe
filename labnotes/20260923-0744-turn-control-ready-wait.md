# Turn-control ready wait

The concurrent five-file Call Engine STS group (93 tests) failed once on seed
0 and once on seed 1 at `STSTurnControlTest.start_session/1`'s default
100-ms `assert_receive` for the exact session's asynchronous `:ready` event.
Different turn-control cases failed on each seed; the isolated four-test file
passed. `Speech.Session.start/2` permits a five-second default startup budget
(`@timeout 5_000`), so the test's 100-ms observation window is not the owned
contract. This is a reproduced test-boundary failure under contention, not a
reason to widen a runtime timeout. The milestone records the separate repair
before editing the test helper.

The helper now waits at most 5,000 ms for the exact allocation's `:ready`
event; it leaves the runtime budget and subsequent self-requeued acknowledgement
unchanged. The four-test file passes 4/0, and the same 93-test concurrent group
passes on seeds 0 and 1. This repair is test-only. A scoped Astra xhigh review
found the one-line test-boundary repair sound; it changes no runtime timeout or
protocol. Committed separately as `bcdbe43d`.
