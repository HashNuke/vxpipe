# Tenant phone application API

C3b1 follows committed D1 and precedes the C3b2 Console form. The focused binding
decision records its design review separately from implementation completion.

- Reuse primary scoped Telnyx registration and credential locks. Operator input is
  limited to service name, application ID and optional outbound caller number.
- Keep application identity and generated media ingress stable across edits. An
  application-ID change must reject old prepared references. No credential copies.
- Read published phone routes from the existing call-spec deployment store; no
  second routing configuration. Exclude drafts, superseded revisions and foreign
  tenants; retain ambiguity information even when the display is bounded.
- Keep the old credential inventory contract intact. Applications have a separate
  safe operator directory. No remote provisioning or new call-spec editor is added.
- Begin with focused red tests at the owning Calls/Persistence/Console boundaries.

## Implementation and verification

- Five initial Persistence integration tests failed because the operator application
  boundary did not exist. After implementation they passed. Three initial Console
  tests failed on missing HTTP routes; the endpoints now pass all three.
- The first HTTP rerun exposed a fixture error: the test read a fresh page's CSRF
  token but reused the earlier session cookie. Keeping the token with its page's
  cookie corrected the fixture; production CSRF protection was unchanged.
- The expanded Persistence group passed 20 tests, including application/route limits
  and a duplicate beyond the displayed route limit. The authorization/input test
  was then moved to the Calls application that owns it; the four-test Calls group
  passes. Persistence retains storage, credential and published-route integration.
- Public writes force the primary Telnyx binding, generate media ingress identity,
  and edit only application ID/outbound number by tenant plus canonical service ID.
  Existing locked resolution rejects stale prepared references after an ID change.
- Directory reads exclude drafts, superseded revisions and foreign tenants. SQL
  window counts mark ambiguity before the 500-route limit. The 100-application
  limit is independent of the existing credential inventory contract.
- Review covered operator/CSRF authorization, input allowlists, tenant ownership,
  stable identity, conflict rollback, fail-closed tenant overrides and safe output.
  Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. The final umbrella suite is running.
- This checkpoint changes no UI and claims no rendered or live-provider acceptance.
  C3b2 owns the Console form and browser checks; D2 owns combined final acceptance.

- First full umbrella run: 1,798 tests, one failure, 40 excluded. Calls (117),
  Persistence (184) and Console (185) passed, as did MCP, AgentRuntime, Engine and
  Artifacts. Gateway's existing five-participant WebRTC handoff test timed out waiting
  for its native adoption gate. Investigating independently before final acceptance.
- The failing native handoff case passes three isolated reruns unchanged. No timeout
  increase or speculative runtime fix was made. Commit the reviewed API boundary as
  a coherent checkpoint; leave C3b1's acceptance checkbox open until a final full run
  passes. UI work remains in the separate C3b2 checkpoint.
