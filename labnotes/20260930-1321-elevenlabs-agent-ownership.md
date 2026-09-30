# ElevenLabs agent ownership

## Starting checkpoint

The preceding goal turn is progress: `1e79ef87` implements and pushes hosted-agent
codec/socket/API preparation and one selected native conversation. All five root
gates pass, with 2,959 default tests and zero failures. Full conversational STT
and room-capable STS remain open. Preserve the unrelated user documentation
content configuration. Gateway implementation stays deferred.

## Ownership and rationale

Remote creation/signing cannot block the eventual session's input/policy control
loop, and allocation teardown must not kill deletion work. The provider-owned
`AgentLeaseSupervisor` lives beneath CallEngine outside the allocation. It starts
empty, explicitly named, before room supervision for reverse shutdown order.
Temporary controllers monitor session owners; separately supervised request
workers monitor controllers and retain `AgentAPI.with_agent` until checked deletion.
No native speech capability is registered by this change.

Readiness returns a private signed connection, not a conversation acknowledgement.
Release acknowledges retirement promptly, with terminal cleanup delivered only
after the explicit deletion result. Owner loss while creating suppresses a late
connection but still retires the returned resource. Worker telemetry carries a
PID/fixed outcome without private payloads, even after the owner/controller dies.

## Red-green and integration evidence

- Initial ownership tests fail 3/3 because the supervisor/controller are absent
  (seed 900956); they then pass (seed 239588).
- Cleanup-failure observation fails before payload-free terminal telemetry is
  added to the independently owned request worker (seed 765680).
- Application supervision placement fails before the named resource supervisor
  is installed ahead of the room subtree (seed 249675).
- The initial graceful-shutdown test fails: the request receives `:shutdown`
  before deleting its prepared agent (seed 309019). The worker now traps only
  its supervising parent's lifecycle exit and completes deletion through the
  active API operation. Its explicit shutdown budget covers bounded API stages.
  Ten ownership/application checks then pass (seed 369548).
- Integration through the installed supervision tree invokes the real `AgentAPI`
  with a synthetic HTTP Plug. It verifies create/sign paths, private auth and
  exact owned deletion, requiring an explicit 204 before terminal observation.
  This is local HTTP execution, not a paid provider call.
- Releasing an already retired controller fails with `:noproc` (seed 309994).
  Handling only normal/already-gone exits makes that acknowledgement idempotent
  without swallowing other call failures. Hard controller death also verifies
  independent request-owner deletion.
- The final combined local codec/API/socket/lease/application lane passes
  37 tests, zero failures, including one loopback socket case, seed 911500.

## Boundaries still open

This is a consumer-ready local ownership component, not room-capable STS. A
killed request worker, VM loss or ambiguous create response still needs durable
identity/reconciliation evidence before production provisioning acceptance.
Neither zero retention nor hosted conversation-record deletion is claimed.
The [ownership design](../docs/elevenlabs-agent-ownership.md) records the local
review separately from acceptance. Call-spec agent/tool configuration, native
session state, credit, interruption, policy, history, usage, scoped publication
and Console acceptance remain required. Standalone Scribe turn ownership is
still separate and unfinished. No previously passing paid test is repeated.

All five root gates terminate successfully: format check, warnings-as-errors
compile, strict Credo (1,167 files, no issues), default test and unused dependency
check. The default suite passes 2,968 tests with zero failures and 89 exclusions,
seed 149103: CallEngine 1,761; Gateway 522; Console 194. This ownership change does
not modify a speech/source state machine; the eventual STS integration still
requires its own Lean and room acceptance. No UI files changed in this checkpoint.
