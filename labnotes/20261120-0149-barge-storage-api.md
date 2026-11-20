# Barge-in storage and API

## Scope

Implement the optional versioned `barge_in` evidence field on human turn diagnostics,
with bounded identity/timing validation, durable record codec support and authorized
turn JSON exposure. The interrupted output identity is separate from the enclosing
human source and turn. The endpoint is server egress acknowledgement, not remote
audible stop. Existing end-of-turn durations and quality remain independent.

The parent owns Engine correlation and integration; another agent owns frontend.
No commits, deployment, live providers or Telnyx work from this task. Coordinate
all Mix runs with the parent to avoid concurrent shared-build work.

## Red-green verification

Focused model, durable revision/legacy roundtrip and authorized API tests have been
written before implementation. Initial runs are pending the shared Mix lane.

## Implementation

Added `Vxpipe.Calls.BargeIn` to validate the exact version-1 envelope, six interrupted
output identity fields, bounded nullable timing/sample fields, server-egress
boundary and explicit unavailable reasons. Available durations must equal stop
minus onset and satisfy playback/onset/request/stop ordering. Late confirmation
may follow stop. Unavailable entries retain nil duration. Unknown/private fields,
overlong identities, unsupported boundaries, invalid ordering and invented
arithmetic are rejected. Envelope omission counts require the entry-limit reason.

`TurnDiagnostic` accepts this optional field with a nil legacy default. Its existing
end-of-turn quality and derived metrics are unchanged. Persistence uses the existing
JSON record column; no migration is needed. The codec extends only fixed key/enum
lookups. The authorized turn presenter includes the snake_case field, preserving
microseconds and identities rather than implying remote audibility.

## Verification evidence

Initial red runs: Calls constructor 10 tests / 2 expected failures; selected durable
roundtrip 1 / 1 expected failure; selected authorized API 1 / 1 expected failure.
All rejected the previously unsupported field before implementation.

After implementation and formatting:

- Calls TurnDiagnostic: 10/10, seed 839924.
- Persistence LatencyStore: 19/19, seed 17329. The suite's deliberate unreachable
  database case logs connection refusal at port 1; the suite passes. New evidence
  covers a legacy absent field, available revision, incomplete revision with
  omitted entries, exact rereads and stale-revision rejection.
- Console CallLatencyEndpoint: 11/11, seed 839860. New evidence verifies both
  authorized route aliases expose exact barge-in evidence and private no-store
  headers; existing authentication checks remain green.

Logs: vxpipe-barge-storage-calls-red.log, vxpipe-barge-storage-persistence-red.log,
vxpipe-barge-storage-api-red.log, and corresponding -green.log files.
`git diff --check` passes. All Mix sessions are terminal and the lane returned to
the parent. No full suite, live network provider, deployment or commit was run.
Independent review and whole-feature integration remain parent-owned and pending.
