# Outgoing calls and two-call live telephony

Status: complete after review corrections (2026-10-06). Review of `b1fd2f57`
observed four failures in nine Telnyx → Twilio live reruns. The six corrections and ten
consecutive passing live runs in each direction are now recorded in the
[review-fix milestone](outgoing-call-review-fixes.md), with fixes committed as `817453a4`.
Final verification passes all root gates and Lean; the full umbrella reports 3,192 tests,
zero failures and 104 exclusions (seed 394892). Historical single-run evidence follows below.

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
  connects and must differ from the caller/callee. An incoming handler may be an agent
  or human; an outgoing handler must be an agent because the outgoing API supplies no
  human-handler join route or token.
- The callee's destination comes from `number` or protected `number_from_variable` (initial
  variables). The originating number is the telephony service's configured outbound number;
  call spec input cannot supply it. Publication and new claims require that originating
  number under the existing service lock, including after caller ID is removed from a
  published service.
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
  call record and unique per tenant: the same key and request returns the original admitting,
  running or ended call with `200` and does not dial again. A failed start replays its original
  `503` error/body with `retryable: false`; another attempt requires a new key. The same key
  with a different request returns `409`; without the header every request is a separate call,
  as R39 decided for preparation. Incoming calls need no key: carrier event and leg identities
  already deduplicate them.
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
  first message with a distinct short marker (`Alpha.` or `Bravo.`). It answers other speech
  with only its own marker, allowing reciprocal proof if peer startup misses the first utterance.
  Pass: each human participant's final transcript contains the other side's marker, then the
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
- [x] Run once against real accounts and record the created resource names (no secrets/IDs that
  identify billing). Both providers provisioned 2026-10-04; a no-purchase repeat reports all found.

### Checkpoint D: outgoing calls

Implement in this order; each sub-checkpoint is a coherent commit with its tests and docs.

D1. Call spec schema (CallEngine, Calls)
- [x] Red validation cases: exactly one of `incoming_call`/`outgoing_call`; caller is a human
  with a `receive` + `start_call` connection; callee is a human with a phone `dial` connection;
  `handled_by` exists and differs and is an agent for outgoing calls; `ring_timeout_ms`
  default and bounds; transfer dial unchanged.
- [x] New schema version `20261004.01`; `20260915.01` specs still parse (translated) and save,
  publish and run; examples and authoring docs updated.
- [x] Saving an outgoing spec creates no inbound participant or telephony route.

D2. Plan and persistence (CallEngine, Calls, Persistence)
- [x] Resolved plan carries direction and ring timeout; plan digest covers them; historical
  stored plans decode as incoming.
- [x] Migration: `outgoing_outcome`, `idempotency_key`, `idempotency_digest` on calls, with a
  partial unique index on tenant + key.

D3. Engine flow (CallEngine)
- [x] Room start with `handled_by`; dial through the outbound connector; callee media joins as
  an ordinary participant; first message after the callee's media connects.
- [x] Ring deadline and every dial outcome end the room exactly once; late/duplicate callbacks
  ignored; remote hangup after answer uses the existing lifecycle.

D4. Gateway outcome propagation and media join (Gateway)
- [x] Outgoing leg reports the normalized end reason to the room; transfer behavior unchanged.
- [x] Outbound media for an outgoing entry joins as a participant, not a transfer destination.

D5. API (Gateway HTTP, Calls)
- [x] Route, `calls`-scope authentication, published revision, error shapes, `201` response.
- [x] Optional `Idempotency-Key`: same key and request returns the original call without a
  second dial; same key with a different request returns 409; absent key dials every time;
  concurrent duplicates dial once.

D6. Observability and docs
- [x] Call details/inspection show `outgoing_outcome`, dial submitted/answered/ended times;
  no private payloads.
- [x] Architecture, user API docs, call spec reference and examples.

### Checkpoint E: live acceptance

- [x] Twilio → Telnyx and Telnyx → Twilio answered calls with two-way audio evidence in ten consecutive current passing runs each; current counts and seeds are in the review-fix milestone.
- [x] Unanswered dial ends at its ring deadline.
- [x] Record evidence here and in the index; record carrier limitations honestly.

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
- Live commands (checkpoint E), after D's runtime/API implementation:

  ```shell
  bin/livetests telephony:status
  bin/livetests run --only live_telephony apps/vxpipe_console/test/integration
  ```

- Provisioning blocker cleared 2026-10-04 after the user created the Twilio compliance profile.
  No additional number purchase is needed. A–E are implemented and accepted; use selected
  cases above for later verification rather than running every live provider.

## Acceptance and failure checks

- [x] Current reliability acceptance: a saved, published outgoing call spec places a call
  through either carrier, carries reciprocal greeting transcripts, and closes both rooms
  in ten consecutive passing runs per direction. Historical single-run evidence below is
  superseded by the 2026-10-06 review and its linked fixes milestone.
- [x] Non-answer outcomes end the room once; callbacks cannot redial or revive it.
- [x] Cross-tenant, unauthenticated, draft-only or incoming-spec requests never dial.
- [x] A live run needs no personal phone number and leaves no Funnel mapping or node running
  that it started.
- [x] Provisioning without `--allow-purchase` never spends money; re-running changes nothing.

## Scope boundaries

No automatic redial, voicemail delivery, campaign or bulk dialing, scheduling, carrier fallback,
number release or Twilio trial-account support. Account-wide carrier settings need explicit
authorization; the user approved only low-risk US/Canada voice dialing on 2026-10-05, with both
high-risk categories disabled. Destination rate limiting and allowed-destination policy are
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

At this initial attempt, the Twilio number and two-provider live acceptance waited for the user
to complete Twilio Trust Hub verification. This blocker was subsequently cleared, as recorded below.

### Provisioning recheck at the user's request

On 2026-10-04, before proceeding with D, `telephony:status` confirmed the existing Telnyx
resources and missing Twilio number. One `telephony:provision --allow-purchase` attempt reused
all Telnyx resources and again failed at Twilio with HTTP 401, primary compliance profile not
approved. No call was placed and no new purchase succeeded.

All six requested settings are present in the runner's child environment. Tailscale OAuth
accepted the client ID/secret pair; the existing node and Funnel served the production Gateway
public endpoint test (1 test, zero failures, seed 530653), then were stopped. Telnyx REST
authentication works and its public key has valid 32-byte Ed25519 encoding; the key's account
match remains unverified until real signed callbacks arrive. Twilio REST discovery works, so
the purchase blocker is the reported compliance restriction. See the
[verification table](../live-telephony-harness.md#provisioning-verification-2026-10-04) and
[labnote](../../labnotes/20261004-2330-telephony-provisioning-check.md).

At this recheck, checkpoint C's real-account gate remained unchecked. Checkpoints D and E remained open. The next
local implementation sequence remains D1 schema, D2 plan/persistence, D3 engine, D4 media/outcomes,
D5 API/idempotency, and D6 observability/documentation; the user requested provisioning first.

### Successful provisioning after Trust Hub setup

The user reported creating a Twilio compliance profile. One subsequent
`bin/livetests telephony:provision --allow-purchase` reused the three Telnyx resources,
purchased one Twilio US local number and set its Voice URL/method to this machine's fixed route.
Both providers returned `ready`. A subsequent run **without** `--allow-purchase` reported
all resources `found` and exited successfully. Resource names are `vxp-test-rocksalt` for the
Telnyx outbound profile, Voice API application and number tag, and for the Twilio number's
FriendlyName. Provisioning is complete; signed carrier callbacks and call audio still await E.

### Accepted direction schema and storage checkpoint

D1 and D2 passed all root gates on 2026-10-04: format, compile with warnings as errors,
strict Credo, unused dependency check, and the full umbrella suite (3,050 tests reported,
zero failures, 98 excluded, seed 263210). Focused tests went red before the direction,
plan defaults, storage metadata and uniqueness changes. Legacy sources continue to save,
publish and run; new incoming source runs, outgoing publication creates no inbound route,
and the ring deadline changes the deterministic preparation digest. All three livetests
shell suites passed with fake carriers. Both updated JSON examples parsed successfully.
See the [direction reference](../call-spec-direction.md) and
[checkpoint labnote](../../labnotes/20261004-2326-outgoing-direction-schema.md).

The selected public endpoint test also passed through the normal runner and carrier preflight
(1 test, zero failures, seed 771983), then stopped the test node/Funnel. D3–D6 and E remain
unchecked; no live calls or paid AI/speech tests were run during this checkpoint.

### Initial outgoing runtime checkpoint (2026-10-05)

The engine prepares the handler before a single supervised dial and holds first-message
speech until accepted submission and callee media. A correlated owner monitor and one
absolute ring deadline normalize non-answer exits, reject delayed answers after deadline,
and cancel pending submission work when the room stops. The readiness budget includes
ring time; an early media attachment is reconciled after submission.

Gateway forwards authenticated outcomes to the exact room attempt, attaches initial media
with main admission, and leaves DTMF transfer acceptance in the transfer path. Initial
room loss cancels its known carrier leg. An uncertain submission retains a bounded owner
for late identity/acceptance cleanup and never redials; timeout does not destroy that owner.
Configured AMD holds media until classification, so a machine result stops before greeting.
Unknown classification permits an answered call without treating it as human proof.

Red-green evidence: 64 focused engine tests and 27 Gateway tests, zero failures. Format,
compile with warnings as errors, strict Credo and unused dependency checks passed. Full
umbrella verification for this runtime checkpoint passed: 3,078 tests, zero failures. See the
[runtime labnote](../../labnotes/20261004-2357-outgoing-room-runtime.md).
The [runtime decision](../outgoing-call-runtime.md) records ownership, uncertain submission
cleanup and the rejected transfer/synchronous-dial alternatives.

D3 stays unchecked until native STS generated opening and the remaining runtime contracts
are verified. D4 passed all root gates: 3,078 tests, zero failures across all nine
applications. D5 must add an initial submission
acknowledgement that survives a prompt terminal outcome; D6 must project the new outcomes
and timestamps through archive, call details and inspection. No live calls were placed.


### Durable admission checkpoint (2026-10-05)

D5's Calls/persistence slice passes focused tests: one tenant-scoped admitted outgoing
call from the explicit publication pointer; no join token; calls-scope authorization;
canonical idempotency replay/conflict; one winner among eight concurrent requests;
fresh credential authorization inside the insertion transaction; duplicate recovery
after database rollback. Focused regressions passed: Calls 28 tests, Persistence 30
tests, zero failures. HTTP/runtime submission acknowledgement remains unimplemented,
so D5's acceptance tasks remain unchecked. See the
[admission labnotes](../../labnotes/20261005-0037-outgoing-call-admission.md) and
[runtime decision](../outgoing-call-runtime.md). All root gates now pass for this slice: 3,088 tests, zero failures, 98 excluded,
seed 303119 across nine applications; format, compilation with warnings as errors,
strict Credo and unused dependency checks passed. No live calls ran.

### HTTP submission checkpoint (2026-10-05, accepted)

The tenant outgoing route now requires `calls` scope and a published outgoing spec,
returns bounded management errors and waits for a correlated submission acknowledgement.
Same-key replays return the original call directly; changed requests conflict, and concurrent
duplicates submit one dial. No-key requests create independent calls. The room defers startup
until its running state and incarnation are durably saved. Projection failure, cancellation
or controller loss before release prevents dialing. Accepted/unknown acknowledgement survives
a prompt terminal exit, including an authenticated end before the worker returns.

Focused regressions passed: 69 engine tests, 50 Gateway tests, seven Calls workflow tests and
five PostgreSQL workflow tests. Root format, warnings-as-errors compile, strict Credo and
unused dependency checks passed. The full root run passed across all nine applications:
3,104 tests, zero failures, 98 excluded, seed 755205. D5 is complete. Lean build, oracle and
Elixir replay passed after the cutover fixture adjustment. See the [HTTP labnotes](../../labnotes/20261005-0102-outgoing-http-submission.md)
and [runtime decision](../outgoing-call-runtime.md). No carrier calls ran; D3 native STS,
D6 outcome/timestamp projection was accepted in the following checkpoint; E remains open.

## D6 acceptance: outgoing lifecycle projection (2026-10-05)

The engine emits one bounded dial-submitted, answered and ended fact, also visible through
live inspection. Calls validates the closed payloads. Persistence archives and projects them
under the tenant/call/incarnation lock, retaining the first outcome and timestamps. Answered
survives hangup; a later answer cannot replace a non-answer terminal result. Archive closure
fills missing dial-end evidence after abrupt room termination. Unproven interrupted attempts
are unknown; known preparation failure is failed without fabricated dial times. Closure after
HTTP failure retains the failed state/reason. SQL rejects inverted timestamps and an answer
timestamp without an answered outcome; closure clocks retain microseconds.

Existing call-details/inspection endpoints expose `outgoing_outcome`, `dial_submitted_at`,
`answered_at` and `dial_ended_at`, with no request keys or provider payloads. Incoming inspection
retains its call-object shape. Projection is asynchronous, so fields can remain null until
evidence is stored. The [runtime contract](../outgoing-call-runtime.md#outgoing-lifecycle-projection),
[API guide](../operator-api-key-authoring.md#starting-an-outgoing-call), direction reference and
[complete outgoing example](../../examples/call-specs/outgoing-morse.json) are updated.
The example parses and compiles through the real capability registry without provider requests.

Focused checks passed: 32 engine/archive tests, 19 outgoing PostgreSQL tests, the 43-test
persistence regression group before the last preparation-closure addition, and 10 Console
inspection tests. All five root gates passed: format, warnings-as-errors compilation,
strict Credo (1,189 files), unused dependencies and **3,121 tests, zero failures, 98 excluded**,
seed **219668**, across all nine applications. Full persistence includes the last added test.
Evidence and fixture corrections are recorded in the
[D6 labnotes](../../labnotes/20261005-0203-outgoing-lifecycle-projection.md).
No rendered UI change or browser verification is claimed by this API projection checkpoint.
No carrier calls or paid AI/speech requests ran. D3 native STS opening and all E acceptance
cases remain unchecked; the milestone itself is not complete.


### Native turn STS opening checkpoint (2026-10-05)

Turn Morse generated/fixed openings now wait for callee media, speak once, and publish
agent evidence without a fake caller turn. Google fixture coverage includes both response
profiles, generated opening, exact provider-transcript validation before fixed output,
interruption, missing/different text, bounded assembly and rejection of a replacement cue.
84 focused tests pass (seed 34032). See the [native opening decision](../native-sts-opening.md)
and its [labnotes](../../labnotes/20261005-0227-native-sts-opening.md) for red/green evidence
and limitations. All final root gates pass: 3,134 tests, zero failures, 98 excluded,
seed 269987; strict Credo checks 1,193 files with no issues. Final Lean build/oracle/replay
also pass. GPT-Live/Morse duplex support remains open; D3 stays unchecked. No paid request or live carrier call was made for these tests.

### Native duplex STS opening checkpoint (2026-10-05)

Morse duplex now queues generated `HELLO` or exact fixed text as an agent operation,
without a caller turn or `RECEIVED` prefix. Outgoing room tests decode actual credited PCM
after the callee media gate and reject repeated-answer playback.

GPT-Live now uses a once-only trusted instruction, retaining the original engine response
context while real input silence advances its timeline. Fixed output stays private until
an acoustic burst closes and its aligned transcript exactly matches the requested text
within captured PCM duration. Missing/altered text, interruption, connection loss, bounds
or deadline failures release no unverified audio. Verified output still requires ordinary
room admission and credits; no hidden model/TTS or fake caller input is introduced.
The [opening decision](../native-sts-opening.md) records the acoustic-boundary and provider
transcript limits; [duplex labnotes](../../labnotes/20261005-0318-duplex-sts-opening.md)
record red/green evidence and refactoring.

161 focused duplex regressions pass (seed 546518). Final root gates all pass: formatting,
warnings-as-errors compilation, strict Credo (1,196 files, no issues), unused dependencies,
and **3,143 tests, zero failures, 98 excluded, seed 949782** across nine applications.
Lean build/oracle/replay also passes (one replay test, seed 145929). D3 is now checked;
the milestone index remains unchecked until all E gates pass.

Fresh read-only carrier status still finds both machine numbers and the Telnyx profile/app.
A child-only presence check reports all six requested telephony/Tailscale variables plus
Gemini and Deepgram keys present, without displaying values or making provider requests.
No calls, paid speech/model requests, purchases, or commits occurred in this checkpoint.
All three E acceptance cases remain open; preparation is recorded in the
[acceptance labnotes](../../labnotes/20261005-0347-live-telephony-acceptance.md).

## E harness implementation and partial live evidence (2026-10-05)

Console now owns the assembled encrypted two-carrier fixture and opt-in live cases in
`test/integration/live_telephony_test.exs`. Local checks cover publication/binding, API
authentication, native speech preparation while dialing is held, one production outgoing
submission through a simulated carrier, and signed incoming admission over the real HTTP
listener. **Five tests pass, four live cases excluded** (seed 700659). Twilio rejection
telemetry exposes only bounded numeric status/code and operation; **eight adapter tests pass**
(seed 678850), including poisoned/non-numeric codes. Return values and retry behavior are
unchanged. Strict Credo, formatting, warnings-as-errors compilation and unused dependency
checks pass. The pre-hangup-repair root suite reports **3,151 tests, zero failures, 103 excluded**
(seed 930118). Console's 200 default tests pass; the loopback HTTP case is now explicitly
integration-tagged and passes when selected. Earlier root runs failed Engine's source-cutover
busy poll and Gateway's synthetic phone-transfer recovery speech. Bounded cutover state
polling and an acknowledged recovery-stream delta now pass both complete owning suites in
the umbrella run (1,881 Engine and 545 Gateway tests). At this stage the three live gates
remained open; the final acceptance below supersedes that status.

The user approved enabling only low-risk US/Canada voice dialing after Twilio error 21215.
One-country (`US`) API update and a subsequent GET verified low-risk true, both high-risk
flags false. Provisioning itself still never changes Geo Permissions automatically.

The Console lane now distinguishes local tailnet HTTPS from public Funnel ingress. It
resolves public IPv4 relay addresses, preserves hostname/SNI and certificate verification,
and requires bounded public health before a paid dial. Its signed synthetic public case
passed (seed 217713) while a parent kept the node online. Immediate public runs can still
fail before submission; the first unanswered selection did so (seed 743241), placing no call.
This prevents an unavailable public endpoint from consuming an otherwise valid dial attempt.

A selected Twilio → Telnyx call created its receiving room via the real signed Telnyx
platform webhook and was answered: **TELNYX_PUBLIC_KEY is now verified against this account's
callbacks**. Reciprocal remote transcripts failed (seed 778738); Twilio reported WebSocket
protocol error 31924. Telnyx delivery records show HTTP 200 for initiated/answered and later
streaming stop. No two-way audio or natural room/archive closure claim follows from this.
The Telnyx → Twilio attempt also lacks answered audio evidence. A selected native Deepgram
TTS probe passed real synthesis/completion (seed 15667), and read-only speech/model auth
checks returned HTTP 200. All three E acceptance gates remain unchecked.

A further selected call (seed 386272) verified Twilio's exact WSS signature, both HTTP 101
upgrades, both carrier start formats and incoming media. It exposed a local fixture error:
24 kHz TTS was rejected by Gateway's 48 kHz output contract. A focused wire-URL assertion
failed with 24000; changing fixture TTS to 48000 passes all five local cases (seed 687328).
Both carriers' authentication now has live evidence, but reciprocal speech and closure
still require acceptance. Production signature/media validation was not changed.

Short marker greetings and marker-only replies now pass reciprocal human transcripts in
the Twilio-to-Telnyx direction (seeds 327674 and 201787). A stale durable incarnation ID in
the monitor helper was reproduced locally and repaired using the public live participant
snapshot; five local cases pass (seed 54330) and Console's 200 default cases pass (seed 210099).
At that point the live closure check confirmed the outgoing room ended but the incoming room
missed its ten-second bound. Production `CallAdmission.handle_live_event/5` then had
no terminal-event handler. E remained open pending an exact-incarnation carrier hangup path,
both complete directions and the unanswered case. The sequential selection stopped at the
first failure and did not dial the remaining two cases.

## E live acceptance and incoming hangup repair (2026-10-05)

All three required live cases pass on the repaired incoming lifecycle:

| Selected case | Seed | Required evidence |
| --- | --- | --- |
| Public signed admission (no carrier call) | 784537 | Public Funnel and signed synthetic incoming admission |
| Twilio → Telnyx | 106192 | Real signed ingress, both human remote marker transcripts, both room monitors DOWN, both durable archives closed, answered outcome and dial timestamps |
| Telnyx → Twilio | 662627 | The same reciprocal speech, signed media and natural closure requirements in the opposite direction |
| Unanswered Twilio → Telnyx | 247633 | No receiving route; one submission; `no_answer`; no answer timestamp; five-second ring bound plus the existing bounded margin |

Each selection passed one test with eight excluded. The parent kept the test node online
between selections, submitted each carrier case once and stopped the node afterwards.
`tools:status` confirms it is stopped. No personal destination, new purchase, retry or further
account-wide setting change was needed.

Gateway now forwards an authenticated, correlated incoming terminal event before or after
media start. Engine ends only the exact tenant/room/incarnation through its trusted public
`end_call/3` operation; ordinary supervision closes the archive. Twilio's owned bidirectional
stream stop is normalized as terminal only after account/call/stream validation. Generic
socket disconnect and Telnyx stream-stop behavior retain their existing semantics. See the
[hangup decision](../carrier-hangup-lifecycle.md).

Focused evidence: 19 Engine lifecycle tests, 43 Gateway carrier/decoder/ingress tests, and
20 lifecycle/platform-tool tests on the final policy extraction pass. Strict Credo, formatting,
warnings-as-errors compilation, unused dependencies and Lean build/oracle/replay pass. The
full umbrella recheck passes **3,156 tests, zero failures, 103 excluded** (seed 930118).
The last accepted predecessor was 3,151 tests; the repaired lifecycle adds five focused
Engine/Gateway cases. Final EndCall policy extraction additionally passes its 20-test
lifecycle/platform-tool group. Those single-run E requirements and the final root gate passed on 2026-10-05. The 2026-10-06 review reopened current acceptance; this historical evidence does not complete the milestone.

Funnel startup can close some advertised public relay connections while others work.
Acceptance used a bounded ten-minute stabilization pass requiring all advertised IPv4 relays
healthy for three consecutive probes before the free admission check and paid selections.
This does not prove immediate startup availability; ordinary selected runs can fail at public
health before dialing. No paid test is automatically retried. See the
[final checkpoint labnotes](../../labnotes/20261005-0927-carrier-hangup-lifecycle.md).

See [selected commands and evidence](../live-telephony-harness.md#e-implementation-and-live-evidence-2026-10-05)
and the [acceptance labnotes](../../labnotes/20261005-0347-live-telephony-acceptance.md).
