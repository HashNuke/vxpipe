# Outgoing calls and two-call live telephony

Status: specification proposed (2026-10-03); design review pending. Checkpoints A (`bin/livetests run`) and B (public test endpoint) are implemented; C (carrier provisioning) is implemented and Telnyx is provisioned, while the Twilio number purchase awaits the user's Trust Hub compliance approval.

Prerequisites: [Telnyx calls](telnyx-calls.md), [Twilio through the common telephony
contract](twilio-calls.md) (adapter, incoming and transfer dialing), [prepared call
admission](prepared-call-admission.md), [tenant call specs and API keys](tenant-call-specs-and-api-keys.md),
[tenant-scoped provider credentials](tenant-provider-credentials-and-platform-configuration.md).
Sources: [live telephony harness decision](../live-telephony-harness.md),
[tenant telephony services](../tenant-telephony-services.md), [opt-in live provider
tests](../live-provider-tests.md), [G2 admission routes](../call-spec-gap-review.md#g2--resolved-for-the-initial-scope-admission-authentication-and-entry-roles),
[architecture: initial outbound machine detection](../architecture.md).

## Runnable outcome

A tenant backend calls one authenticated API naming a published call spec route and a
destination. Vxpipe starts the room with the agent, dials the human through the call spec's
telephony service, and either continues the conversation when answered or ends the room when the
leg is not answered by its ring deadline, is busy, fails or reaches a machine. An operator proves
this against both carriers with `bin/livetests run`, which has Vxpipe call its own numbers on this
machine's public Tailscale endpoint, without any personal phone number.

## Specification

### Call spec: outgoing entry caller

- Permit `connection.mode: "dial"` with `admission: "start_call"` only on the `entry_caller`
  participant. Today `ConnectionIntent` rejects any dial admission other than `transfer`.
  Dial transfer connections keep their current meaning.
- The destination comes from the existing `number` or protected `number_from_variable`
  (initial variable). The originating number is the telephony service's configured outbound
  number; call spec input cannot supply it.
- Add optional `ring_timeout_ms` to an outgoing entry connection: default 30,000, bounded
  5,000–60,000. It covers dial submission through answer; it is not reset by ringing events.
- Answering-machine detection keeps its existing service-level configuration. Per the
  architecture's initial-outbound rule, a machine result ends the attempted call without
  voicemail speech; unknown or disabled detection is not proof of a human.
- Save, publish and preparation run the existing telephony service/credential guards. Publishing
  yields a participant connection key for the outgoing entry caller as it does for web entries;
  verify and reuse the current route mechanism rather than adding a parallel one.

### Outgoing call API

```http
POST /api/tenants/{tenant_key}/participants/{participant_key}/outgoing-calls
Authorization: Bearer <tenant API key>
Content-Type: application/json

{"initial_variables": {...}}
```

- Authenticated exactly like the existing preparation route; no CORS grant. The participant
  key must resolve to a published outgoing entry caller; a web or receiving route returns 422.
- Calls prepares and pins the plan and variables (the existing preparation path), the room
  starts with the `entry_receiver` agent, and the dial is submitted through the existing
  outbound leg connector with fresh service/credential resolution.
- Respond `201` with the call ID and initial status once the room exists and the dial was
  submitted. Outcomes are observable through existing call details/inspection. Validation and
  guard failures return the existing management error shapes; dial submission failure ends the
  room and is recorded with an internal-only reason.
- Following R39, there is no idempotency key; a repeated request is a separate call. The
  review must confirm this remains acceptable when each request places a paid call.
- The agent's opening/greeting waits until the leg is answered and media is connected.
- Every non-answer outcome (no answer by `ring_timeout_ms`, busy, rejected, failed, machine,
  unknown submission) ends the room exactly once with a typed reason. Duplicate, late or
  out-of-order callbacks cannot redial or revive it. Remote hangup after answer uses the existing
  participant/room lifecycle.

### Live test tooling: `bin/livetests`

As decided in the [harness decision](../live-telephony-harness.md):

- `bin/livetests run [mix test args]` replaces `bin/test-live-providers` with the same child-only
  credential loading, placeholder clearing and ambient-credential isolation. With no arguments it
  runs every live lane.
- `tools:up|down|status` manage this machine's `vxp-test-<machine>` userspace Tailscale node and
  its port-443 Funnel. `run` starts tools for telephony selections, exports
  `TELEPHONY_TEST_PUBLIC_URL` and `TELEPHONY_TEST_PORT` to the child, and stops only what it
  started, including on failure and interrupt. A per-machine lock prevents concurrent runs.
- `telephony:provision [--allow-purchase]|status` find or create the Telnyx application,
  outbound profile and tagged number, and the Twilio `FriendlyName` number, all named
  `vxp-test-<machine>`, and point them at this machine's fixed test routes.
- Env file settings reduce to `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TELNYX_API_KEY`,
  `TELNYX_PUBLIC_KEY`, `TAILSCALE_CLIENT_ID` and `TAILSCALE_CLIENT_SECRET`; `TELEPHONY_TEST_PUBLIC_URL` stays an
  optional override that disables Tailscale management.

### Two-call live acceptance

- Console owns the live cases because they compose Calls, Persistence, Gateway and Engine.
  They use the ordinary persistence test database configuration; no database settings are passed.
- The test starts the production gateway endpoint on `TELEPHONY_TEST_PORT`, checks
  `<public URL>/healthz` through Funnel, then checks carrier state read-only.
- Fixture tenant: an outgoing call spec on service A (agent first, dial entry caller) and a
  receiving call spec published on service B's number. Services use the provisioned resources
  and disable machine detection.
- Cases: Twilio → Telnyx and Telnyx → Twilio each prove answer, a known phrase heard in both
  rooms' transcripts, and clean hangup of both rooms; an unanswered dial proves Room A ends at its
  ring deadline with the expected reason.
- Prefer deterministic local Morse speech and scripted agents to avoid model/speech cost, if
  Morse survives carrier transcoding; otherwise use the cheapest configured STT/TTS.

## Implementation checklist

### Checkpoint A: `bin/livetests run`

- [x] Rename the runner shell test first and run it red against the missing `bin/livetests`.
- [x] Add `bin/livetests` with `run` and `help`, preserving current runner behavior; remove
  `bin/test-live-providers`.
- [x] Update `AGENTS.md`, `docs/live-provider-tests.md`, the env example and milestone references.

### Checkpoint B: public test endpoint

- [x] Shell tests with a fake `tailscale`/`tailscaled` for name derivation, OAuth registration
  parameters (`ephemeral=false&preauthorized=true`, `--advertise-tags=tag:vxp-test`), refusing an
  existing 443 mapping, cleanup of only owned mappings, lock contention and the override path.
- [x] Implement `tools:up|down|status` and automatic start/stop in `run`.
- [x] A tagged live test starts the gateway endpoint on `TELEPHONY_TEST_PORT` and reaches
  `/healthz` through the public URL.

### Checkpoint C: carrier provisioning

- [x] Tests against fake carrier HTTP servers: find-only, create-missing, purchase refused without
  `--allow-purchase`, second run is a no-op, nothing is released, other machines' resources are
  untouched.
- [x] Implement `telephony:provision` and `telephony:status` for Telnyx and Twilio.
- [x] Read-only preflight used by live tests, with explicit failure messages.
- [ ] Run once against real accounts and record the created resource names (no secrets/IDs that
  identify billing).

### Checkpoint D: outgoing calls

- [ ] Red call spec validation cases: dial `start_call` accepted only for `entry_caller`,
  `ring_timeout_ms` bounds, existing transfer dial unchanged.
- [ ] Publish/route resolution for outgoing entry callers.
- [ ] API route, authentication, wrong-route rejection and response.
- [ ] Room start, dial through the outbound connector, greeting after answer.
- [ ] Fake-carrier outcomes: answered, no answer at deadline, busy, failed, machine, unknown
  submission, duplicate/late callbacks, remote hangup; one room end each.
- [ ] Call details/inspection record dial outcome and timings without private payloads.
- [ ] Architecture and user documentation for the API and call spec fields.

### Checkpoint E: live acceptance

- [ ] Twilio → Telnyx and Telnyx → Twilio answered calls with two-way audio evidence.
- [ ] Unanswered dial ends at its ring deadline.
- [ ] Record evidence here and in the index; record carrier limitations honestly.

## Acceptance and failure checks

- [ ] A saved, published outgoing call spec places a call through either carrier with no
  provider-specific room logic.
- [ ] Non-answer outcomes end the room once; callbacks cannot redial or revive it.
- [ ] Cross-tenant, unauthenticated or wrong-route requests never dial.
- [ ] A live run needs no personal phone number and leaves no Funnel mapping or node running
  that it started.
- [ ] Provisioning without `--allow-purchase` never spends money; re-running changes nothing.

## Scope boundaries

No automatic redial, voicemail delivery, campaign or bulk dialing, scheduling, idempotency keys
(pending review), carrier fallback, number release, Twilio trial-account support, or changes to
account-wide carrier settings. Destination rate limiting and allowed-destination policy are
recorded as follow-up review items, not implemented here.

## Specification review

Pending. Review should confirm the R39 idempotency position for paid outgoing calls, the
`ring_timeout_ms` bounds, and whether a destination policy must precede exposing the API.

## Checkpoint A evidence

`test/shell/livetests_test.sh` (renamed from `live_provider_runner_test.sh`) first failed with
`bin/livetests: No such file or directory`. `bin/test-live-providers` moved to `bin/livetests`
with `run`, `help` and usage errors (exit 2) for a missing or unknown command; `run` keeps the
existing child-only credential loading, placeholder clearing and ambient isolation, now also for
`TAILSCALE_CLIENT_ID`/`TAILSCALE_CLIENT_SECRET`. The shell test then passed. Current docs,
`AGENTS.md` and the env example use `bin/livetests run`; historical labnotes keep the old name.

## Checkpoint B evidence

`test/shell/livetests_tools_test.sh` uses fake `tailscale`/`tailscaled` binaries. It first failed
on the missing public URL, then passed after `tools:up|down|status`, automatic start/stop in
`run`, the per-machine lock and the override path were implemented. It caught a real defect:
inside an EXIT trap a bare `return` reports the status from before the trap, so after a failing
test run `set -e` aborted the cleanup. All returns are now explicit.

The secret reaches `tailscale up` through `--auth-key=file:` with a 0600 file removed immediately,
so it never appears in a process listing. Real runs on rocksalt (2026-10-04):

```text
$ bin/livetests tools:up
vxp-test-rocksalt https://vxp-test-rocksalt.<tailnet>.ts.net -> http://127.0.0.1:4600
$ bin/livetests tools:down
$ bin/livetests run --only live_telephony \
    apps/vxpipe_gateway/test/integration/public_telephony_endpoint_test.exs
1 test, 0 failures            # node and Funnel started by run, stopped afterwards
```

Public DNS (1.1.1.1) resolves the name to Tailscale Funnel relays, and a throwaway local server
answered through it before the gateway test was written.

The first root-level live run stopped at test database creation: `config/test.exs` defaulted to
TCP localhost, which requires a password on this host. It now prefers the local Unix socket
(peer authentication) when `PGHOST` is unset; the same run then passed with no database
environment variables.

## Checkpoint C evidence

`test/shell/livetests_telephony_test.sh` drives a fake `curl` holding Telnyx v2 and Twilio REST
state. It first failed because the commands did not exist, then passed for: refusing to buy
without `--allow-purchase`, creating and wiring every resource with it, a no-op second run,
repairing drifted webhook/Voice URLs, leaving another machine's tagged resources untouched,
read-only `telephony:status`, credentials only in curl's stdin config, exporting discovered
numbers so each provider calls the other, and refusing a run against an unprovisioned account.

The first real run exposed a defect: Twilio refused the purchase, yet the command printed `ready`
and exited 0, because bash ignores `set -e` inside command substitutions evaluated in `||`
conditions. A red case reproduced it; each carrier step now returns 1 for missing and 2 for an
error, and an error stops the command. Twilio account SIDs are masked in error output.

Real accounts (2026-10-04):

```text
$ bin/livetests telephony:provision --allow-purchase
telnyx   outbound profile         created vxp-test-rocksalt
telnyx   voice API application    created vxp-test-rocksalt
telnyx   number                   bought +1435XXXXXXX
livetests: POST .../IncomingPhoneNumbers.json returned HTTP 401: Primary compliance profile is
not approved. Please refer to documentation and complete the KYC process in Trust Hub ...
$ bin/livetests telephony:provision
telnyx   ... found (all three)
twilio   number                   missing (re-run with --allow-purchase to buy a US local number)
```

Blocked: the Twilio number, and therefore every live call, waits for the user to complete
Twilio Trust Hub verification.

