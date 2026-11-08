# Bounded session reuse

Baseline: `877fd37b`, committed and pushed with all root gates passing. T1 has
four of five items complete; the full milestone still has 25 open items.

The previous checkpoint reproduced reused-session credential resolution surviving
both a 100 ms opening deadline and host shutdown (two failing probe cases).
This checkpoint adds canonical boundary tests before changing production code.
It must bound authorization and readiness together, cancel only the new opener's
work, and acknowledge local worker termination before returning failure. Delayed
supervisor admission must not release expired work. A retiring session must reject
new reuse authorization before invoking the resolver.

The independent Astra design review also reproduced a normal-caller-exit gap in
an isolated model of the proposed nested Task/HTTP-helper approach. It was not
shown reachable through synchronous `Connections.open`; it is a design concern,
not an additional production bug. That proposed design is not implemented.
The original caller must be monitored explicitly, and merely stopping an outer
waiting Task is insufficient evidence that the actual credential worker stopped.
Root-owned renewal cancellation acknowledgement remains a separate T3 contract.

## Implementation and reproductions

- Canonical reuse tests initially failed eight of nine cases (seed 639534):
  authorization survived deadline/host loss/close, readiness exceeded its budget,
  and retirement still invoked current credential resolution. The caller-death
  case also showed that authorization was running in the original opener.
- Two startup-tail tests failed before the fix: an arbitrary runtime status
  callback could outlive startup/client death, and failed initialization could
  block on a suspended host's `terminate_child`. Independent review reproduced
  both through the public opening API.
- `SessionOperation` runs one temporary task under the existing transport
  supervisor. `SessionLifecycle` owns admission, original caller monitoring and
  deadline cancellation; it performs neither callbacks nor supervisor calls.
  Bounded admission cannot release callbacks after timeout. Worker termination
  precedes completion, with a finite local observation cap and honest incomplete
  cleanup result. No new permanent process or dependency patch is introduced.
- Review then reproduced a concurrent-publication race: a second opener could
  succeed before the original opener failed, and the original failure retired
  the published session. The canonical test failed (three cases, one failure,
  seed 761185). Atomic lifecycle startup abandonment now preserves a published
  session and retires only an unpublished startup.
- Fourteen focused reuse/readiness tests pass (seed 578282), including independent
  concurrent reuse, late successful callback publication and traced queued child
  admission. The earlier combined connection/ownership/telemetry selection passes
  45 cases. Final review and umbrella gates are still running.
- The added TLS fixture holds a real connection after ClientHello. Its first
  attempts failed due to fixture configuration: production loopback rejection,
  resolver arity, then mismatched trusted origin. The isolated loopback profile
  now overrides the actual wire URL and exact trusted origin to TLS. OTP may emit
  both cancellation and close alerts; the fixture drains those under one deadline
  before asserting TCP closure. These were fixture corrections, not dependency
  behavior fixes.

## Completed transport acceptance

The TLS fixture now also establishes a complete initialize/GET/initialized
exchange, finishes its chunked stream correctly, then holds the reconnecting
GET's TLS handshake after ClientHello. Session close, normal host stop, host kill
and client kill all produce exact integration/client/transport DOWN and peer TCP
closure. The four initial-POST and four resumed-GET cases pass together (eight
tests, seed 717711). Earlier fixture iterations exposed unsupported default test
certificate signing and a truncated HTTP stream; explicit test RSA/SHA256 keys
and valid chunked EOF correct the fixture without changing production behavior.

Certificates are generated in memory with OTP's documented
[`pkix_test_data/1`](https://www.erlang.org/doc/apps/public_key/public_key.html#pkix_test_data/1)
and remain confined to loopback tests. No certificate/key files or dependency
changes are introduced.

Independent Astra review audited T1 against its whole checklist and approves the
final standalone lifecycle box with the completed root gates below. Earlier pinned
patch preparation/upgrade evidence remains applicable because dependency sources
are unchanged. Participant composition, root-owned renewal acknowledgement and
catalog maintenance remain later milestone requirements.

## Umbrella verification finding

The first root run (seed 303343) reproduced a pre-existing speech fixture race in
`SpeechToSpeechOutputSTTTest`: synchronous `input_finished` emission exited with
`:killed` because successful recognition legitimately retires the emitting
provider before its GenServer reply. One hundred focused repetitions passed,
so the full-run failure is the reproduction evidence, not a claim of a reliable
focused failure. The known-failing umbrella process was stopped explicitly.

Five terminal emissions now use the fixture's existing cast path, with their
transcript, completion, usage and process-DOWN assertions preserved. The one
intentionally suspended-capability test keeps its synchronous enqueue assertion;
that test cannot retire the provider until the capability resumes. No speech
runtime or state machine changed. Focused verification and independent review of
this synchronization correction precede the new full root run. The focused file
passes all 29 tests with the original root seed 303343, and independent review
approves the correction without changing the assertions under test.

## Final gate progress

- Combined connection/ownership/telemetry and all lifecycle lanes: 102 tests,
  zero failures, seed 609400. This includes all eight real TLS connect cases.
- Official conformance, exact-version SSE recovery, Everything reference server,
  isolated checks and runtime credential/privacy selection: 28 tests, zero
  failures, seed 378989.
- Format, dev/test warnings-as-errors compilation, strict Credo and unused
  dependency checks pass. Local documentation links and whitespace checks pass.
- The replacement full root run passes with seed 303343: 5,042 tests, zero
  failures, 316 excluded. All ten umbrella applications completed and the command
  exited successfully. Four tagged GET cases added after the default MCP suite
  ran are independently covered by the combined 102-test lane. The earlier stopped
  run is failure evidence, not completion evidence.
- All five root gates and the independent T1 acceptance audit pass. T1 is complete
  (five of five implementation items); T2, T3, T3b and T4 remain open, with 24 of
  the milestone's 29 implementation items pending. The full milestone is not
  complete. The final staged evidence review precedes commit and push.
