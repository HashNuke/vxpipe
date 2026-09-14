# Incoming leg lifetime

## Reproduction and decision

The first deterministic phone run passed startup readiness and silent disconnect, but six failure
cases left their socket open after the room and model worker stopped (`vxpipe-initial-wait-phone.log`).
The incoming leg only consumed provider events and had no room-lifetime monitor. Its socket watched
the leg, while the media session watched the room; stopping the media session alone left the phone
leg and socket alive. This matters before media connects too, so a media-session-only notification
would leave an answered but unconnected failed call behind.

Add a small trusted engine monitor boundary that selects tenant, logical room and exact incarnation
without attaching a participant. Its focused test first fails because that boundary does not exist
(`vxpipe-room-monitor-red.log`), then passes tenant/incarnation rejection and expiration delivery
(`vxpipe-room-monitor-green.log`). The existing incoming leg owns the monitor and retains its pinned
service. Room loss submits one provider-neutral hangup and retires the leg; existing socket and
admission monitors then close/revoke their resources. If the room already disappeared by activation
completion, end the leg immediately. No new process or supervision tree is introduced. Custom
backend activation results retain their existing lifecycle ownership.

The configured provider adapter is retained only in the internal activation result; its Inspect
projection excludes the service. The engine lookup is bounded to one second and monitors the
captured process, so a later incarnation cannot inherit this leg. The ending path uses the existing
adapter and usage-cancellation contracts. This is explicit lifecycle work, not terminate/2 cleanup.

Phone checks pass 18 tests (`vxpipe-initial-wait-phone-final.log`): both providers' original incoming
transfer flows plus startup success, blocked STT, model failure, both clocks, silent disconnect,
and failures before any media socket connects. Failure checks require one exact provider hangup;
connected failures also require socket termination. They do not claim physical carrier audibility.
Focused engine opening/lifecycle/telemetry checks pass 50 tests (`vxpipe-initial-wait-engine.log`).

## Verification scope

This is the phone-lifetime checkpoint discovered while accepting initial waiting. It owns the
engine's exact-incarnation monitor and the incoming leg's pinned-service cancellation; no provider
restart or call-definition change is required. The companion initial-wait checkpoint owns the late
wait-player regression and WebRTC configuration matrix. Keep the two purposes in separate commits.
The combined working tree passes all five root gates: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`, `mix test --max-cases 4`, and
`mix deps.unlock --check-unused`. The final test run has 1,362 tests, zero failures and 15
exclusions (seed 307676; `vxpipe-initial-wait-completion-gates-*`). Gateway contributes 366 tests
and the engine 625. The final focused phone rerun passes 18 tests without compiler warnings
(`vxpipe-initial-wait-final-phone.log`). Test case selection uses ExUnit tags to avoid
compile-time constant-comparison warnings without changing the case matrix.
