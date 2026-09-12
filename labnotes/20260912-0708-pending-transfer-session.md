# Pending transfer session

## Checkpoint: reproduced the gateway/client contract mismatch

During the pre-delivery durable-call review, the gateway accepted the transfer
destination and returned HTTP 201, but the transfer console reported an invalid
participant session. The pending-transfer response projected only the participant
ID, role, and state. The shared sample-client participant contract also requires
the pinned room and incarnation IDs.

The focused gateway response test now asserts those two identifiers before the
implementation changes. This preserves the externally observable boundary that
failed in the browser.

Red evidence:

- `cd apps/vxpipe_gateway && mix test test/vxpipe/gateway/http/call_admission_test.exs`
  failed only in `issues a provisional session without joining a transfer-only
  human`; the returned participant lacked `room_id` and `incarnation_id`.
- `cd apps/vxpipe_console/assets && npm test -- --run
  src/sampleAdmission.test.ts` failed because the runtime guard accepted a
  participant without its declared `room_id`.

## Checkpoint: aligned the pending participant projection

The gateway now copies the room and incarnation identifiers from the pinned
running call into its provisional participant projection. It does not fabricate a
joined participant snapshot: the destination remains in `pending_transfer` until
the private-briefing and acceptance barriers commit the transfer. The sample
client guard now requires the room identifier promised by its TypeScript contract.

Green evidence:

- The focused Gateway admission file passes 14 tests.
- The focused sample-admission and transfer-page files pass 2 tests, and
  `npm run check` passes.
- The full Console suite passes 88 tests; all Console assets pass 8 tests across
  4 files plus TypeScript checking.
- The full Gateway suite passes 227 tests with 6 integration tests excluded.
  Running it concurrently with the live development stack and the Console suites
  first exposed unrelated 100-millisecond process-monitor assertion timeouts in
  two different tests. Each exact failure passed immediately, and the whole
  Gateway suite passed after the live stack was stopped; no production or test
  change was needed.

## Rendered regression verification

The durable development sample ran over HTTPS against the isolated migrated
`vxpipe_review` database with the configured Gemini model and local Morse audio.
In the caller tab, `Transfer me to human support` produced the allowlisted
`transfer` function call. In the second tab, the same real gateway endpoint that
previously failed now progressed through:

1. `Requesting destination admission`
2. `Destination media connected`
3. `Private briefing opened`
4. `Destination accepted transfer`

The page displayed `Private briefing line open` and enabled `Accept transfer`;
there was no invalid-participant-session error. The local Morse briefing did not
finish inside the definition's unchanged 30-second total transfer deadline, so
this run intentionally does not claim main-room activation. The existing real
two-peer Gateway integration test remains the evidence for completed playback,
activation, and bidirectional human audio. This browser run verifies the response
contract regression itself.

## Final verification

- `mix format --check-formatted`, warnings-as-errors compilation, the unused-lock
  check, and strict Credo all pass; Credo reports no issues across 802 source files.
- The first umbrella attempt mistakenly supplied the runtime database variable
  instead of the test-specific variable and eventually collided on Repo startup.
  With `VXPIPE_TEST_DATABASE_URL` set correctly, one Calls test failed once and
  passed under `mix test --failed`; a subsequent clean full umbrella run completed
  every child application with zero failures.
- `git diff --check` passes.
