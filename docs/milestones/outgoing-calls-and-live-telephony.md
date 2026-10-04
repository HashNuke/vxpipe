# Outgoing calls and two-call live telephony

Status: specification reviewed (2026-10-04). Checkpoints A (`bin/livetests run`) and B (public test endpoint) are implemented; C (carrier provisioning) is implemented and Telnyx is provisioned, while the Twilio number purchase awaits the user's Trust Hub compliance approval.

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

### Call spec: call direction

A call spec declares exactly one direction block naming its two starting participants; having
both or neither is rejected. This replaces `entry_caller`/`entry_receiver` under a new schema
version.

```json
{
  "incoming_call": { "caller": "customer", "handled_by": "assistant" },
  "participants": {
    "customer":  { "type": "human",
                   "connection": { "service": "support-phone", "mode": "receive",
                                   "admission": "start_call", "number": "+14155550199" } },
    "assistant": { "type": "agent", "prompt": "..." }
  }
}
```

```json
{
  "outgoing_call": { "callee": "customer", "handled_by": "assistant", "ring_timeout_ms": 30000 },
  "participants": {
    "customer":  { "type": "human",
                   "connection": { "service": "support-phone", "mode": "dial",
                                   "number_from_variable": { "section": "customer", "variable": "phone" } } },
    "assistant": { "type": "agent", "prompt": "...", "first_message": { "mode": "generated" } }
  }
}
```

- `incoming_call.caller` is the human expected to call in; its connection is `receive` with
  `admission: "start_call"` on a phone service or `web`. `outgoing_call.callee` is the human
  Vxpipe dials; its connection is `dial` on a phone service (`admission` may be omitted for the
  callee and is implied). `handled_by` is the participant that talks to that human when the call
  connects, usually an agent; it must differ from the caller/callee.
- The callee's destination comes from `number` or protected `number_from_variable` (initial
  variables). The originating number is the telephony service's configured outbound number;
  call spec input cannot supply it.
- `outgoing_call.ring_timeout_ms` is optional: default 30,000, bounded 5,000–60,000. It covers
  dial submission through answer and is not reset by ringing events.
- Other participants and transfers are unchanged and work in either direction. `dial` with
  `admission: "transfer"` keeps its current meaning for transfer destinations.
- Compatibility: specs saved under the previous schema version stay readable and executable;
  `entry_caller`/`entry_receiver` are read as `incoming_call.caller`/`handled_by`. Stored
  compiled plans remain decodable. Internal Elixir field names may keep their current names;
  renaming them is a separate mechanical change, not required by this milestone.
- Answering-machine detection keeps its service-level configuration. Per the architecture's
  initial-outbound rule, a machine result ends the attempted call without voicemail speech;
  unknown or disabled detection is not proof of a human.
- Save and publish run the existing telephony service/credential guards for the callee's service.

### Agent speaks first

The existing `first_message` setting of the `handled_by` participant controls the opening:
`wait_for_input` (silent until the human speaks), `generated` (the model composes an opening from
its prompt) or `fixed` (exact `text`).

- In an outgoing call the first message starts when the callee answers and their media is
  connected, never when the room starts, so the agent never greets a ringing phone.
- When `handled_by` sets no `first_message` in an outgoing call spec, it defaults to
  `generated`, so the agent introduces itself; the prompt should say who it is and why it is
  calling. `wait_for_input` remains available explicitly. Incoming call specs keep the current
  `wait_for_input` default.

### Outgoing call API

```http
POST /api/tenants/{tenant_key}/call-specs/{call_spec_id}/outgoing-calls
Authorization: Bearer <tenant API key>
Idempotency-Key: 4f9c2a1e-...          (optional)
Content-Type: application/json

{ "initial_variables": { "customer": { "phone": "+14155550123", "name": "Dana" } } }
```

```http
201 Created
{ "call": { "id": "...", "call_spec_id": "...", "revision": 3,
            "state": "running", "outgoing_outcome": null } }
```

- Addressed by call spec, beside the existing `/api/tenants/{tenant_key}/call-specs` API, and
  authenticated with a tenant API key like the existing preparation route; no CORS grant.
- Requires an API key with the `calls` scope (as preparation does; `admin` alone is not enough).
- Uses the call spec's currently published revision. A draft-only, unknown, foreign or incoming
  call spec returns the existing management error shapes (404/422). Initial variables are
  validated against the spec's declared sections as in preparation.
- Calls prepares and pins the plan and variables, the room starts with `handled_by`, and the dial
  is submitted through the existing outbound leg connector with fresh service/credential
  resolution. Respond `201` once the room exists and the dial was submitted.
- Optional client-generated `Idempotency-Key` (a UUID or similar opaque value), stored on the
  call record and unique per tenant: the same key and request returns the original call with
  `200` and does not dial again; the same key with a different request returns `409`; without the header every request
  is a separate call, as R39 decided for preparation. Incoming calls need no key: carrier event
  and leg identities already deduplicate them.
- `state` is the existing call record state (`running` once the room exists). The dial result
  is the new `outgoing_outcome`: `null` while ringing, then exactly one of `answered`,
  `no_answer` (carrier no-answer or local ring deadline), `busy`, `rejected` (remote hangup before
  answer), `failed`, `machine` or `unknown` (submission result unknown). Read it from the
  existing call details/inspection endpoints. Every non-answer
  outcome ends the room exactly once with a typed reason; duplicate, late or out-of-order
  callbacks cannot redial or revive it. Remote hangup after answer uses the existing
  participant/room lifecycle. Dial submission failure ends the room with an internal-only reason.

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

- Console owns the live cases (`apps/vxpipe_console/test/integration/`, tags `:live_providers`
  and `:live_telephony`) because they compose Calls, Persistence, Gateway and Engine. They use
  the ordinary test database; no database settings are passed.
- `bin/livetests run` exports `TELEPHONY_TEST_PUBLIC_URL`, `TELEPHONY_TEST_PORT`,
  `TELNYX_APP_ID`, `TELNYX_TEST_FROM` (Telnyx number), `TWILIO_TEST_FROM` (Twilio number), the
  carrier credentials and `TELNYX_PUBLIC_KEY`. The test serves the production gateway endpoint
  with telephony enabled (`public_base_url` = `TELEPHONY_TEST_PUBLIC_URL`, real Calls/Persistence
  repositories) on `TELEPHONY_TEST_PORT`, then requires `/healthz` through the public URL as
  `apps/vxpipe_gateway/test/integration/public_telephony_endpoint_test.exs` does.
- Fixture tenant (created in the test database by the test):
  - Telnyx credential at **platform** scope (API key + public key) and a Telnyx service with
    `provider_connection_id` = `TELNYX_APP_ID` and `outbound_number` = `TELNYX_TEST_FROM`.
    Platform scope is required because provisioning points the Telnyx application at
    `/webhooks/platform/telnyx`.
  - Twilio credential (SID/token) and a Twilio service with `ingress_key` **`vxp-test-twilio`**
    (the provisioned Voice URL) and `outbound_number` = `TWILIO_TEST_FROM`.
  - Machine detection disabled on both services.
  - Per direction: an outgoing call spec on the dialing provider's service and an incoming call
    spec published on the other provider's number.
- Speech: use the existing `gemini-3.5-flash-lite` model selection (as in
  `examples/call-specs/development.json`) and Deepgram STT/TTS. Each `handled_by` uses a `fixed`
  first message with a distinct phrase (for example "vxpipe outbound check alpha" and "vxpipe
  inbound check bravo"). Pass: each room's transcript contains the other side's phrase, then the
  test ends Room A and both rooms end. Morse speech is optional, cost-free extra evidence only.
- Unanswered case: dial the other number while it has no published incoming route, with
  `ring_timeout_ms: 5000`. Assert Room A ends within the deadline plus a bounded margin with a
  non-answer `outgoing_outcome`, and record which one the carrier produced. The exact
  `no_answer` timer path is proven locally with fake carriers.
- Each answered case costs two short US calls plus model/STT/TTS usage; keep runs bounded and
  never retry automatically.

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
  identify billing). Telnyx done 2026-10-04; Twilio purchase awaits Trust Hub approval.

### Checkpoint D: outgoing calls

Implement in this order; each sub-checkpoint is a coherent commit with its tests and docs.

D1. Call spec schema (CallEngine, Calls)
- [ ] Red validation cases: exactly one of `incoming_call`/`outgoing_call`; caller is a human
  with a `receive` + `start_call` connection; callee is a human with a phone `dial` connection;
  `handled_by` exists and differs; `ring_timeout_ms` default and bounds; transfer dial unchanged.
- [ ] New schema version `20261004.01`; `20260915.01` specs still parse (translated) and save,
  publish and run; examples and authoring docs updated.
- [ ] Saving an outgoing spec creates no inbound participant or telephony route.

D2. Plan and persistence (CallEngine, Calls, Persistence)
- [ ] Resolved plan carries direction and ring timeout; plan digest covers them; historical
  stored plans decode as incoming.
- [ ] Migration: `outgoing_outcome`, `idempotency_key`, `idempotency_digest` on calls, with a
  partial unique index on tenant + key.

D3. Engine flow (CallEngine)
- [ ] Room start with `handled_by`; dial through the outbound connector; callee media joins as
  an ordinary participant; first message after the callee's media connects.
- [ ] Ring deadline and every dial outcome end the room exactly once; late/duplicate callbacks
  ignored; remote hangup after answer uses the existing lifecycle.

D4. Gateway outcome propagation and media join (Gateway)
- [ ] Outgoing leg reports the normalized end reason to the room; transfer behavior unchanged.
- [ ] Outbound media for an outgoing entry joins as a participant, not a transfer destination.

D5. API (Gateway HTTP, Calls)
- [ ] Route, `calls`-scope authentication, published revision, error shapes, `201` response.
- [ ] Optional `Idempotency-Key`: same key and request returns the original call without a
  second dial; same key with a different request returns 409; absent key dials every time;
  concurrent duplicates dial once.

D6. Observability and docs
- [ ] Call details/inspection show `outgoing_outcome`, dial submitted/answered/ended times;
  no private payloads.
- [ ] Architecture, user API docs, call spec reference and examples.

### Checkpoint E: live acceptance

- [ ] Twilio → Telnyx and Telnyx → Twilio answered calls with two-way audio evidence.
- [ ] Unanswered dial ends at its ring deadline.
- [ ] Record evidence here and in the index; record carrier limitations honestly.

## Implementation guide

Findings from the 2026-10-04 handover audit. Paths are starting points; verify behavior before
changing it, and keep each change in the application that owns it.

### Schema and compatibility (D1–D2)

- `Vxpipe.CallEngine.CallSpec` (`apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_spec.ex`)
  accepts exactly one `@schema_version` (`validate_schema/3`). Accept both versions: parse the new
  shape for `20261004.01`, and translate `entry_caller`/`entry_receiver` from `20260915.01` into
  an incoming direction before validation. Saved revisions keep their stored source, so old
  revisions must keep compiling.
- `entry_caller`/`entry_receiver` appear in ~134/119 files, including the `calls` table columns
  (`apps/vxpipe_persistence/lib/vxpipe/persistence/schema/call.ex`), `PreparedCall`,
  `PreparedCallFactory`, `TrustedCall`, Console presenters and samples. Do not rename internals in
  this milestone: keep the plan and column fields, filling them with caller/callee and
  `handled_by`. Add explicit direction instead.
- `ConnectionIntent` currently requires `admission: transfer` for `dial`. Allow `start_call` only
  when the participant is `outgoing_call.callee`; the callee may omit `admission`.
- `Vxpipe.Calls.CallSpecs` derives routes on save (`participant_routes/3`, `telephony_routes/2`,
  `inbound_telephony?/1`). An outgoing callee must not produce either route kind.
- `OutboundLegRequestResolver.resolve/3` matches only `admission: :transfer`; extend it for the
  outgoing callee using the same `number`/`number_from_variable` rules.
- The plan codec loads fixed atom owners before safe decoding (see tenant telephony services);
  add new atoms there, and decode plans without a direction as incoming.

### Engine flow (D3)

- Startup: `RoomAuthority.Startup` prepares `entry_receiver` and opening audio for
  `entry_caller`. For outgoing plans, after install, submit the dial with
  `OutboundLegConnector.connect/3` (as `HumanDestinationPreparer.prepare_connection/4` does),
  monitor the returned owner, and start the ring timer. Keep this in a dedicated module (for
  example `RoomAuthority.OutgoingCall`), not inside transfer modules.
- First message: `FirstMessage.start/1` runs from `StartupReadiness`
  (`room_authority/startup_readiness.ex`). Outgoing readiness must include the callee's media
  connection, so neither `generated`/`fixed` openings nor opening audio start while ringing.
  `FirstMessage.for_agent_activation` sets `:pending` for non-`wait_for_input` modes.
- Default `first_message`: apply `generated` at compile time when an outgoing `handled_by` agent
  omits it; incoming keeps `wait_for_input` (`CallSpec.Participant`).
- Ending: on a non-answer outcome, disconnect the leg handle, record the outcome and stop the room
  through its existing end path; exactly once, whichever of timer, owner exit or report arrives
  first.

### Gateway (D4)

- `Telephony.Event` already normalizes carrier end reasons to
  `:hangup | :busy | :no_answer | :failed | :timeout`, but nothing forwards them: transfers only
  monitor the `OutgoingLeg` owner (`human_handoff.ex` `monitor_outbound_leg/1`) and
  `OutgoingLeg` stops with `:normal`. Add a provider-neutral way for the owner to report the end
  reason and answering-machine stop (for example a `{:shutdown, {:outbound_leg_ended, reason}}`
  exit reason, or a message to the room), keeping existing transfer handling green.
- `OutgoingLeg` media start calls `MediaSupervisor.start_outbound_session/5` and then
  `report_transfer_control(..., :media_ready)`, wiring media as a transfer destination. Outgoing
  entries must instead attach like the incoming path (`CallAdmission.handle_live_event/5` →
  `MediaSupervisor.start_session/5`): the callee becomes a normal room participant.
- Map before-answer `:hangup` to `rejected`, `:timeout` and the local ring timer to `no_answer`,
  `:busy`/`:no_answer`/`:failed` directly, machine detection to `machine`, and an unknown
  submission to `unknown`.

### API (D5)

- `Vxpipe.Gateway.HTTP.Router` routes every `["api", "tenants", t, "call-specs" | _]` request to
  `CallSpecWrites`. Match `POST [..., "call-specs", id, "outgoing-calls"]` in a clause **before**
  it, and handle it in a new `Vxpipe.Gateway.HTTP.OutgoingCalls` module (not `CallAdmissions` or
  `CallSpecWrites`).
- Authenticate with `Calls.authenticate(tenant, secret, :calls, options)` as `CallAdmission`
  does. Add a Calls workflow (for example `Vxpipe.Calls.OutgoingCalls.start/5`) that fetches the
  published revision, builds the plan with `PreparedCallFactory.build/4` (add an outgoing
  transport), runs the existing credential guards, and inserts the call with the idempotency
  fields in one transaction.
- Idempotency digest: SHA-256 of canonical JSON (`Vxpipe.Calls.CanonicalJSON`) of
  `{call_spec_id, initial_variables}`. On a unique-index conflict, read the existing row and
  compare digests; equal returns it with `200` and no dial, different returns `409`.
- The gateway backend then starts the room and dial, and marks the call `running` or `failed`
  with the existing start/fail projections.

### Verification notes

- Local tests use the existing fake telephony adapters and `TestTelephonyServiceRepository`;
  no live carrier is needed until checkpoint E.
- `bin/verify-lean` is required only if speech source-cutover modules change
  (`verification/Verification/SourceGate.lean`).
- Known unrelated flakes under full-suite load (both pass in isolation): CallEngine
  `SpeechToTextTest` "prepared activity origin stays private…" and Gateway
  `HumanTransferWebRTCTest` "five-participant handoff…". Rerun before attributing failures.

## Handover

- Read `AGENTS.md` (red-green-refactor, SRP, completion gates, labnotes, commit hygiene). Use
  this milestone's labnote, `labnotes/20261003-1700-outgoing-calls-livetests.md`, or create a
  new one with `bin/create-labnotes`.
- Root gates: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test`, `mix deps.unlock --check-unused`, and the shell suites
  `test/shell/livetests*_test.sh` when touching `bin/livetests`. `mix test` needs no database
  environment variables on a host with a local PostgreSQL socket.
- Never read or edit `~/.config/vxpipe/live_providers.env`; credentials reach tests only through
  `bin/livetests run`.
- Live commands (checkpoint E), after the Twilio number exists:

  ```shell
  bin/livetests telephony:status
  bin/livetests run --only live_telephony apps/vxpipe_console/test/integration
  ```

- Blocker for E: Twilio Trust Hub approval, then `bin/livetests telephony:provision
  --allow-purchase` (buys one Twilio US number for this machine).

## Acceptance and failure checks

- [ ] A saved, published outgoing call spec places a call through either carrier with no
  provider-specific room logic, and its agent introduces itself once the callee answers.
- [ ] Non-answer outcomes end the room once; callbacks cannot redial or revive it.
- [ ] Cross-tenant, unauthenticated, draft-only or incoming-spec requests never dial.
- [ ] A live run needs no personal phone number and leaves no Funnel mapping or node running
  that it started.
- [ ] Provisioning without `--allow-purchase` never spends money; re-running changes nothing.

## Scope boundaries

No automatic redial, voicemail delivery, campaign or bulk dialing, scheduling, carrier fallback, number release, Twilio trial-account support, or changes to
account-wide carrier settings. Destination rate limiting and allowed-destination policy are
deferred: the carriers' own destination controls (Telnyx outbound profile countries, Twilio Geo
Permissions) apply meanwhile, and per-tenant limits must be added before API keys are issued to
tenants other than the operator.

## Specification review

Reviewed with the user on 2026-10-04:

- `ring_timeout_ms` defaults to 30,000 and is bounded 5,000–60,000.
- `Idempotency-Key` is optional and honored when passed; the client generates it, because a
  server-generated ID cannot help a client whose response was lost.
- Per-tenant destination and rate limits are deferred until tenants other than the operator
  receive API keys; carrier-level destination controls apply meanwhile.
- Call direction is explicit: `incoming_call {caller, handled_by}` or `outgoing_call {callee,
  handled_by, ring_timeout_ms}` replaces `entry_caller`/`entry_receiver` in a new schema version,
  with previous-version specs still accepted. The user rejected `contact`/`handler` as too vague.
- The API addresses a call spec (`.../call-specs/{call_spec_id}/outgoing-calls`) rather than a
  participant route key, and uses its published revision.
- An outgoing `handled_by` speaks first by default (`first_message: generated`), starting only
  when the callee's media connects.

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
