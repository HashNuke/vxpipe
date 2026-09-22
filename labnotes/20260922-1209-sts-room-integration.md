# STS room integration

Continue directly, preserving the prior worktree; no commits or hosted calls.
Previous checkpoint passed all root gates (2,151 tests, zero failures). That
evidence does not prove a real STS call: existing room tests invoke handlers
against fabricated state, and the ten-session test starts capability trees.

The next regression starts a compiled Morse STS call through the public engine,
attaches a supervised connection and verifies room readiness and scoped cleanup.
Inspection found the room allocation caller discards the policy revision before
calling a helper that expects the policy/revision tuple. Runtime settings also
do not forward the configured STS registry into plan startup. Audio ingress is
not wired to STS yet; do not describe a startup-only test as a full audio call.

## Red-green evidence and repairs

The public `start_call` regression initially failed runtime selection. Forwarding
the STS registry through `RoomSupervisor` exposed the same omission in asynchronous
`RoomAuthority.Startup`; fixing both exposed the predicted policy tuple crash
on connection attachment. With that repaired, the provider became ready but the
room did not: `vxpipe_sts_ready` never restarted startup readiness. After that
repair, disconnecting the source left the capability alive. The room now records
the exact source connection, registers a connection-scoped policy enforcer and
retires that enforcer plus the owned tree on source disconnect.

The startup/disconnect test then passed. Extended it to require the actual STS
resource in the readiness graph; that assertion failed because Inventory omitted
STS and ResourceQuery had no STS adapter. Added the capability's operational
readiness response (including selected output-STT readiness and allocation
identity), the inventory requirement and the closed adapter mapping. The room
and inventory group passed 42 tests.

Replaced the old unit assertion that missing policy means unrestricted access
with a failing assertion requiring explicit unavailability, including a stopped
authority. Allocation now validates the snapshot and never substitutes nil.
A supervised rejecting-policy fixture then proved registration rejection still
bound the candidate. The repair retires the candidate and leaves no binding;
the focused room/readiness/capability/output-STT group passed 74 tests (seed 0).

A further real-attachment assertion proved two source connections were admitted
to the single-source STS room. Admission now returns `:sts_source_already_attached`
for the second source, leaving the original allocation intact. Both real-room
startup/cleanup and rejected-registration tests pass after this refinement.

## Remaining integration work

No public audio turn has been proven in this checkpoint. `CallEngine.push_audio`
still only reaches human-STT ingress; `Ingress.set_sts_target` has no production
caller, and a no-human-STT attachment has no ingress. A bounded, independently
credited and identity/format/policy-checked STS input path is required next.
Caller turn events, actual transcript publication, recording/usage, hold and
transfer scenarios must be verified through the real call path, then the planned
three-mode ten-call comparison. The milestone's room-proof and lifecycle exit
checkboxes are reopened rather than treating capability probes as equivalent.

During the root-suite run, inspected both Gateway speech conversion paths and
the closed descriptor. WebRTC and telephony each derive one speech normalizer
from the STT handle; no second STS handle exists. Google declares its output's
24 kHz in `Descriptor.format` while the input encoder requires 16 kHz, so simply
sharing that format would be wrong. The next-checkpoint decision, rejected
shortcuts and required regression sequence are in `docs/sts-input-routing.md`.
It is not implemented evidence. Also cover attachment before asynchronous entry
preparation, which the current ready-first helper intentionally does not test.

## Checkpoint verification

The refined focused room/readiness/capability/output-STT group passed 74 tests
again with seed 264975. Root format, warnings-as-errors compile, strict Credo,
unused-lock and whitespace checks pass. The final root suite passed 2,153 tests
with zero failures (42 excluded, seed 0), including 1,006 CallEngine tests and
480 Gateway tests. No hosted call, independent review or rendered UI acceptance
was performed here, and the real speech audio route remains unfinished.
