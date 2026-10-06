# Outgoing HTTP submission

This D5 checkpoint connects durable admission to a tenant calls-scoped HTTP operation.
The provider provisioning prerequisite is complete. No live calls or paid speech/model
requests were made during this checkpoint; the runner's private environment file was
neither read nor modified.

## Red-green evidence

The initial HTTP tests failed with 404 because no outgoing route existed. Test-only
syntax and fixture errors were corrected before accepting the red evidence. Calls and
PostgreSQL lifecycle projection tests failed on missing mark-started/mark-failed APIs.
Engine admission tests failed on missing release/cancel operations, preparation before
release, and missing submission acknowledgement. Two further engine cases covered
early authenticated termination while the worker remains pending and cancellation of
an unopened room. A readiness assertion then exposed pending input admission as open;
it was corrected to preparing with the existing startup-readiness error.

The implemented boundary starts only a new claim. It installs an opaque observer and
pending startup controller, synchronously saves the exact room incarnation, then releases
handler preparation and dial. Projection failure and controller loss before release end
the room without dialing. After release, HTTP controller loss no longer owns call lifetime.
The engine sends its one accepted/unknown acknowledgement before a terminal shutdown,
including an authenticated early carrier end while the submission worker is pending.
The HTTP wait is bounded; uncertain submission never triggers an automatic retry.

Focused green: HTTP nine tests (seed 791679); Calls seven (632255); PostgreSQL five
(134980). A broader Gateway group passed 50 tests. Engine initially passed its 23 outgoing
tests, but a 69-test regression group failed two existing lifecycle assertions (571359).
An isolated recheck with seed 791463 failed a different readiness-cancellation assertion;
the lifecycle file alone passed 18 tests with the original seed. These were not ignored:
two default 100 ms waits were made explicit one-second waits, and the wait-player diagnostic
now waits for the model blocker and pins the exact lifecycle process rather than accepting
another room's shutdown telemetry. The 69-test group then passed with seed 571359.

An exploratory malformed-ID persistence assertion passed without a change: IDs are text,
not UUIDs. That dependency-level test was removed, and no ID validation change was made.

## Verification iterations

Root formatting/check, warnings-as-errors compilation, strict Credo (1,186 source files)
and unused dependency checks passed. The full root test process is running with seed
755205 and excludes integration/live-provider lanes. Root results must be recorded here
before marking D5 accepted. Updated the runtime decision, user API request contract and
direction reference; D6 durable outgoing outcome/timestamps and D3 native STS remain open.
Sent the authorized pushnotify update. No commit was created.

The root run passed Engine 1,857 tests and Calls 130, then found one Gateway cutover
fixture failure: its 30 ms deadline elapsed before dispatch, returning deadline_elapsed
instead of the intended suspended-peer source_unavailable path. Gave that fixture a
one-second deadline; the peer remains suspended through expiry, so late epoch rejection
still runs. Its six tests passed with root seed 755205. Lean build/oracle/replay also
passed. No source-cutover implementation or speech state-machine code changed.

The first root run completed across all nine apps: 3,104 tests, one failure, 98 excluded,
seed 755205. The failure was the already-corrected cutover fixture; Gateway reported
541 tests, one failure. Persistence's 196 and Console's 195 tests passed. A fresh full
root run with the same seed is now running against the corrected fixture. The failed
run is not accepted as a green checkpoint.

The same-seed full rerun passed Engine and Calls again, then failed the existing signed
Twilio transfer fixture while waiting two seconds for recovery TTS after destination loss.
The isolated case passed, followed by eleven runs in one VM with the same seed. Extended
that fixture's asynchronous recovery-speech wait to five seconds; it still requires the
expected speech request and subsequent carrier audio, not mere room liveness. Both carrier
harnesses are being checked together before another full gate. Do not count either failed
umbrella run as acceptance. No carrier network requests are made by these fake harnesses.

Final review replaced two newly introduced keyword-list bracket lookups with Keyword.get/2
to comply with repository style. This is a mechanical lookup change; its PostgreSQL
workflow will be rechecked after the running suite. Existing unrelated lookups were left
untouched.

Both fake carrier harnesses passed together: 26 tests, zero failures, seed 755205. The
second full run completed with 3,104 tests, one failure, 98 excluded; only the recovery
fixture failed. Persistence and Console passed again. A third full same-seed run now
includes both fixture adjustments and the keyword lookup cleanup. Sent a second factual
pushnotify update; D5 acceptance is still pending the full gate.

## Next checkpoint research (not implemented)

ArchiveStore already serializes facts under a call-row lock and applies CallEndProjection
inside the fact insertion transaction. The latter currently handles archive closure only,
and carries no outgoing outcome. Engine Recorder can emit bounded private facts without
adding more callbacks to RoomAuthority. D6 should add submission/answer/terminal facts with
only normalized outcome/timestamps, reuse the existing archive and live-inspection ports,
and project them through the locked store before extending the public summaries/details.
No attempt references, phone numbers or provider payloads belong in those lifecycle facts.

Account for failure/closure ordering: HTTP startup failure may mark a running record failed
before archive drains, while ArchiveStore currently rejects failed records. D6 needs focused
tests proving a late terminal projection cannot overwrite the first outcome or be lost
because failure projection won the race. Also pin the answered outcome across a later remote
hangup and enforce timestamp order, exact incarnation and plan binding. Native STS opening
still needs an explicit engine-owned origin rather than filtering a fabricated caller
transcript by text; no native opening operation is implemented here.

Suggested D6 test sequence: Calls-owned fact decoding and closed projection shape; engine
outgoing facts through the existing live-inspection/archive boundary; PostgreSQL projection
of submitted/answered/ended timestamps with duplicate and out-of-order inputs; authorized
inspection and finalized call-details lifecycle fields. The storage tests can extend
outgoing_call_store_test and the existing call_store_test archive insertion boundary;
call_details_source_test and InspectionStore own the public persisted projections. Preserve
the existing room started_at/ended_at meanings when adding dial-specific times. Record
submission before the worker can report an answer, so an early signed outcome has an
ordered local submission timestamp. Verify precision explicitly: the HTTP durable start
uses microseconds, while several engine fact timestamps use milliseconds.

## Accepted local checkpoint

The third full root run completed with exit 0: all nine applications, 3,104 tests,
zero failures, 98 excluded, seed 755205. Gateway passed 541 tests; Persistence passed
196, including the five outgoing workflow tests against the final keyword lookup
cleanup; Console passed 195. Root format, warnings-as-errors compilation, strict
Credo and unused-dependency checks all passed against the final source. Lean build,
oracle drift check and the one Elixir replay test passed (seed 815970).

Marked D5's two acceptance tasks complete and D3's verified deadline/outcome task complete;
the native STS opening task remains unchecked. Synchronized the milestone index, harness
decision, runtime decision, direction reference and user API contract. D6 outcome/timestamp
projection and E's three live acceptance calls remain open. Documentation link/anchor
checks and git diff --check passed. No UI changes, provider purchases, live calls, commits
or changes to the private provider environment file were made in this checkpoint.
