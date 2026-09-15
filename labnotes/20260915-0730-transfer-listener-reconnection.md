# Transfer listener reconnection

Continue after `2d22a5d`, which passed all five root gates with 1,425 tests. The
prior goal turn made progress by committing the native five-participant addition,
independent seven/three-second cursors and immediate attachment hold. Nine
compound milestone tasks remain; the complete changing-audience slice is open.

Extend that running native call by closing one monitor data channel from the
actual WebRTC client, retaining its other connection/player, and attaching a new
connection before delayed support STT permits handoff. Require the original
attempt/deadline and unaffected bindings, then cue-ordered conversation through
both surviving and replacement connections.

The first owning player regression fails: killing one sink reports
`{:failed, :output_unavailable}` instead of sending the next frame to the healthy
sink. Test both pending push and pending playback boundaries. The intended change
removes only a failed sink from a looping multi-output wait; final-output loss,
owner loss and finite-cue failure keep their existing failure behavior.

Evidence so far: `vxpipe-listener-player-red.log` in the local temporary directory.
Native loss/reconnection verification is running; no milestone task is complete
from this change yet. No UI, dependency or dev-server changes are needed.

The two pending-stage player cases both reproduced failure before the change
(`vxpipe-listener-player-red-stages.log`). The native client then reproduced the
same externally visible loss: closing its monitor data channel terminated the
server connection, and waiting audio stopped on the other connection
(`vxpipe-listener-reconnection-red.log`).

The player now removes an unavailable sink from a looping wait only when another
sink remains, releases that sink's pending request/monitor, and lets the retained
acknowledgement advance the existing cursor. Both monitor DOWN and an outstanding
request's process-down response take that path. All nine player checks pass
(`vxpipe-listener-player-green.log`); native reconnection verification is running.

## Policy ownership failure

The native retry still failed after the player fix. The first room failure was
`media_policy_enforcer_unavailable` with a normal connection-child shutdown, not
the player: closing one monitor terminated its room-audio enforcer, which policy
Authority had registered as permanently critical to the entire room. The other
monitor connection therefore lost its room too. The prior status-only goal turn
sent the requested nine-task update; no checkpoint was completed in that turn.

Bind enforcers to the exact connection PID recorded in its authorized attachment.
Do not infer that PID from the process registering the enforcer: registration can
run through a short-lived helper. Connection-owned speech and adopted private
destination enforcers use the same lifetime. Room mixer/router/recording enforcers
retain their room lifetime. Owner monitors retire departed connections, including
when an enforcer DOWN arrives first; a failed enforcer whose connection is still
alive remains fatal. No blanket exception for `:normal` or `:shutdown` is safe.

Three owning policy tests first failed on missing scoped registration/adoption
(`vxpipe-connection-enforcers-red.log`), then all 24 policy tests passed. A fourth
test reproduced departure while policy application was already awaiting an
enforcer (`vxpipe-connection-enforcement-red.log`, 25 tests, one failure). The
barrier now ignores only enforcers whose exact connection has departed, checking
both before application and after a failed acknowledgement. It continues applying
the same revision to every surviving connection. This avoids relying on DOWN
mailbox order or best-effort transport cleanup. Focused engine and native checks
must pass before committing or reporting reconnection acceptance.

## Mixer subscription loss

All 75 focused engine checks passed, including web/phone handoff and the four new
policy cases. Strict Credo passed. The native retry no longer terminated policy
Authority but still stopped all waits. A bounded player trace confirmed it handled
the lost output before its phase owner exited. Tracing the actual handoff result
identified `preparation_conflict` for `room_mixer`: subscriber DOWN had permanently
failed and cleaned the entire pending mixer lease, preventing the same worker from
refreshing its smaller connection set.

The large native module spends about 100 seconds compiling unrelated generated
cases before running this call. For debugging only, a temporary AST extraction
keeps this exact case, setup and helpers and omits other test declarations/loops.
It reproduces the same native failure in 13 seconds. Neither temporary script nor
trace is a product change or final acceptance substitute; the original module
will run in the final umbrella checks.

Two mixer regressions reproduce this for both live and private subscriptions.
Removing one subscriber must keep readiness closed until a refreshed requested set
omits it, then retain the same lease, surviving subscription handle and original
deadline. Trying the still-dead requested subscriber must remain an error. Both
cases first failed (`vxpipe-listener-mixer-red.log` and
`vxpipe-listener-mixer-required-red.log`). Subscription DOWN now removes only that
catalog entry, retaining its missing selection as a readiness failure until an
explicit reconciliation. Phase-owner, deadline and required recording failure
still clean the complete lease. All 13 mixer checks pass; native verification is
running again. No transfer timeout, source capability restart or UI change was
introduced.

## Checkpoint acceptance and review

The same extracted native case passes after the mixer fix (13.7 seconds). All
temporary tracing was removed from the repository test before final verification. The
original native module then passes in the full umbrella: Gateway has 410 tests,
zero failures and seven exclusions; the entire umbrella has 1,433 tests, zero
failures and 16 integration exclusions. The root test uses seed 235296 and maximum
concurrency four. Format checking, warnings-as-errors compilation, strict Credo
and unused-lock checks all pass too. Logs use the `vxpipe-reconnection-final-`
prefix in the local temporary directory; its results JSON records five zero exits.
Documentation links and the nine remaining checkpoint boxes were checked.

Design review: this corrects lifetimes within the existing policy/mixer/player
owners. It adds no handoff coordinator, configuration or timeout extension. A
missing required subscription still prevents adoption; only an explicit refreshed
request changes the required set. Owner/expiry/recording failure still cleans the
whole mixer preparation. The native call retains the original wait player,
attempt/deadline, room services and surviving connection bindings, then proves
cue-before-conversation through both monitor outputs. Durable rationale is in
`docs/incremental-media-policy.md`; the milestone and native guide record the
accepted boundary.

This is a coherent reconnection checkpoint within the changing-listener slice.
Complete listener membership removal/re-entry, changes before acceptance and
repeated human/AI transfers remain open. The count is still nine compound tasks,
including live carrier audio evidence and final audits. The provider prerequisite
blocker does not prevent that remaining local work. Progress notifications were
sent after focused checks and native success.
