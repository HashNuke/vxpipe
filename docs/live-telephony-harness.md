# Live telephony harness

Status: runner, public endpoint and carrier provisioning complete. Both carriers' machine
resources were provisioned 2026-10-04 after the user created the Twilio compliance profile;
repeating provisioning without purchase permission reports all found. The direction schema, plan/storage and initial dial/media checkpoints pass all root gates.
Outgoing API, outcome/timestamp observability, and native turn/duplex STS opening pass
local root gates (3,143 tests, zero failures, seed 949782) and Lean verification.
Both answered directions and the five-second unanswered case now pass live acceptance,
including reciprocal human speech, natural receiving-room shutdown and durable archive
closure. All root gates pass with 3,156 tests, zero failures, 103 excluded (seed 930118), plus
the runner shell suites and Lean verification. Public Funnel startup can require stabilization.
The 2026-10-06 Twilio private-transfer continuation also passes real briefing/press-1, reciprocal
human-bridge speech and selective destination hangup (seed 918113). Final common gates pass with
3,171 default tests, zero failures, 104 excluded (seed 235060), plus Lean verification.
Implementation is tracked by [Outgoing calls and two-call live telephony](milestones/outgoing-calls-and-live-telephony.md)
and [Twilio calls](milestones/twilio-calls.md).

## Decision

Prove Twilio and Telnyx end to end by having Vxpipe call itself, not a person:

```text
Room A: saved outgoing call spec, agent first
  -> provider A dials from this machine's provider A number
  -> this machine's provider B number
  -> provider B incoming webhook -> Room B: published receiving call spec
```

One run covers provider A outbound and provider B inbound; the reversed pair covers the other
two directions. A third case dials a number configured not to answer and expects Room A to end at
its ring deadline. No human destination, verified caller ID or personal phone number is involved.
All numbers are US local numbers and every test call is US to US.

The operator-facing entry point is one command, `bin/livetests`, which replaces
`bin/test-live-providers`:

```text
bin/livetests run [mix test args]      run live tests (credential loading unchanged)
bin/livetests tools:up | tools:down    start/stop this machine's public test endpoint
bin/livetests tools:status             node, public URL, Funnel target, running state
bin/livetests telephony:provision [--allow-purchase]
                                       find or create this machine's carrier resources
bin/livetests telephony:status         what exists for this machine and where it points
bin/livetests help
```

`run` starts the tools it needs and stops only what it started; tools started by `tools:up`
remain up. `run` and `tools:*` never create or change carrier resources; only
`telephony:provision` does, and it buys numbers only with `--allow-purchase`.

### Credentials

The live env file (`~/.config/vxpipe/live_providers.env`, loaded only into the child test
process) needs only:

| Setting | Use |
| --- | --- |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` | Twilio REST authentication and webhook signature verification |
| `TELNYX_API_KEY` | Telnyx REST authentication |
| `TELNYX_PUBLIC_KEY` | Telnyx Ed25519 webhook verification. The Telnyx OpenAPI specification has no endpoint that returns it, so it stays manual. |
| `TAILSCALE_CLIENT_SECRET` | OAuth client secret (`tskey-client-…`); registers this machine's test node |
| `TAILSCALE_CLIENT_ID` | OAuth client ID. Not needed for registration; only used for API checks if the client is later granted read scopes |

`TELEPHONY_TEST_PUBLIC_URL` remains an optional override, for example behind Caddy; when set,
the harness does not start Tailscale. Phone numbers, application IDs and URLs are discovered.

### Public endpoint: a per-machine Tailscale node with Funnel

The harness runs its own `tailscaled` in userspace-networking mode with a dedicated state
directory and socket, registered as `vxp-test-<machine>` with tag `tag:vxp-test`, and funnels
HTTPS port 443 to the gateway listener started inside the test. On `rocksalt` the public origin
is `https://vxp-test-rocksalt.<tailnet>.ts.net`. `<machine>` is `hostname -s`, lowercased and
restricted to `a-z0-9-`, overridable with `VXP_TEST_MACHINE`.

- Tailscale accepts an OAuth client secret directly as `tailscale up --auth-key`, with mandatory
  `--advertise-tags`. Such registrations default to `ephemeral=true` and
  `preauthorized=false`; the harness passes `?ephemeral=false&preauthorized=true` so the node
  keeps a stable name. An ephemeral leftover would push a new node to `vxp-test-<machine>-1`.
- The secret is passed as `--auth-key=file:<0600 file>`, deleted immediately, so it never
  appears in a process listing.
- The node persists its identity in its state directory
  (`~/.local/state/vxpipe/livetests/vxp-test-<machine>/`); later runs reconnect without the
  secret.
- The gateway listener inside the test uses `TELEPHONY_TEST_PORT`, default 4600.
- After enabling Funnel, `tools:up` waits until every relay address in public DNS answers HTTP
  through Funnel, because carriers may reach any relay and relays warm up one by one (69 s
  measured for three relays on 2026-10-06). The wait is bounded by
  `VXPIPE_LIVETESTS_RELAY_TIMEOUT` (default 300 s) and names unreachable relays on failure.
- Funnel listens only on 443, 8443 and 10000. Use 443: Twilio signs the exact callback URL, and
  carrier and SDK handling of explicit non-default ports is inconsistent.
- `tailscale funnel --bg --https=443 http://127.0.0.1:<port>` starts the mapping; the same command
  with `off` removes it. The harness removes only mappings it created and refuses to replace an
  existing 443 configuration on its node.
- `run` holds a per-machine lock so two runs on one machine cannot share the node and numbers.

One-time manual setup in the Tailscale admin console, because no credential exists yet to
script it:

```json
"tagOwners": { "tag:vxp-test": ["autogroup:admin"] },
"nodeAttrs": [{ "target": ["tag:vxp-test"], "attr": ["funnel"] }]
```

then create an OAuth client with the `auth_keys` scope and tag `tag:vxp-test`. The default
policy grants Funnel to `autogroup:member`; tagged nodes are not members, hence the explicit
`nodeAttrs`. Creating the client appears to require the tag to exist in `tagOwners` first
(tailscale/tailscale#20489), so the policy edit precedes it. `tools:up` checks both and prints
the missing step instead of a raw API error.

On `rocksalt` the operator account already has Funnel on 443/8443/10000 and no serve
configuration, verified read-only with `tailscale status --json` and `tailscale funnel status`.

### Carrier resources

Each resource is named for the machine so two machines never route each other's calls.

| Provider | Resource | Idempotency key | API |
| --- | --- | --- | --- |
| Telnyx | Voice API (Call Control) application `vxp-test-<machine>` | `filter[application_name][contains]`, then exact match | `/v2/call_control_applications`; `webhook_event_url`, `outbound.outbound_voice_profile_id` |
| Telnyx | Outbound voice profile `vxp-test-<machine>`, `whitelisted_destinations: ["US"]` | `filter[name][contains]`, then exact match | `/v2/outbound_voice_profiles` |
| Telnyx | US local number tagged `vxp-test-<machine>`, assigned to that application | `filter[tag]` | `/v2/phone_numbers` (`tags`, `connection_id`); purchase via `/v2/available_phone_numbers` then `/v2/number_orders` |
| Twilio | US local number, `FriendlyName` `vxp-test-<machine>` | `FriendlyName` list filter | `IncomingPhoneNumbers`; purchase via `AvailablePhoneNumbers/US/Local` |

`telephony:provision` sets the Telnyx application webhook and the Twilio number's Voice URL to
this machine's public origin and fixed test routes, attaches the outbound profile, and assigns
numbers. Re-running reports `found` and changes nothing. It never releases numbers or changes
account-wide settings such as Twilio Geo Permissions.

On 2026-10-05, a selected outbound call was rejected with Twilio error 21215. The user
explicitly approved enabling low-risk US/Canada voice dialing. A one-country (`US`)
DialingPermissions API update succeeded, and a subsequent read verified low-risk enabled
with both high-risk-special and high-risk-tollfraud disabled. This approved manual exception
does not change `telephony:provision` behavior. In the Console, use Voice → Settings → Geo
permissions and enable only the low-risk US/Canada category. See the
[Twilio API reference](https://www.twilio.com/docs/voice/api/dialingpermissions-bulkcountryupdate-resource).

Telephony runs discover the same resources read-only before starting tests and export them to
the child: `TELNYX_APP_ID`, `TELNYX_TEST_FROM`/`TWILIO_TEST_DESTINATION` (the Telnyx number) and
`TWILIO_TEST_FROM`/`TELNYX_TEST_DESTINATION` (the Twilio number), so each provider calls the
other. Missing or unwired resources stop the run with the provisioning command to fix it. The
Telnyx application webhook uses the platform-scoped route `/webhooks/platform/telnyx`; the Twilio
number's Voice URL uses ingress key `vxp-test-twilio`. Credentials reach `curl` only through its
stdin configuration, never argv, and Twilio account SIDs are masked in error messages.

## Provisioning verification (2026-10-04)

At the user's request, provisioning was checked before continuing outgoing-call implementation.
The existing runner loaded credentials only into a child process; neither the environment file
nor credential values were inspected or displayed. All six named settings were present.

| Settings | Current evidence |
| --- | --- |
| `TAILSCALE_CLIENT_ID`, `TAILSCALE_CLIENT_SECRET` | OAuth token exchange accepted; returned token discarded without logging. Existing test node reconnected and Funnel served the production Gateway `/healthz` test. |
| `TELNYX_API_KEY` | Authenticated resource discovery found this machine's outbound profile, Voice API application and assigned US number, with the expected webhook origin. Provisioning reported all three as found. |
| `TELNYX_PUBLIC_KEY` | Valid Base64 encoding of a 32-byte Ed25519 key. On 2026-10-05, a real signed `call.initiated` callback passed the production platform route and created the receiving room; carrier delivery records also confirm HTTP 200 for `call.answered`. The key matches this account's callbacks. |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` | Authenticated discovery, purchase and configuration succeeded after the user created the compliance profile. A real media upgrade on 2026-10-05 verified the exact WSS signature, returned HTTP 101 and accepted Twilio media frames. |

The public Gateway check passed **1 test, zero failures** (seed 530653), independent of carrier
provisioning preflight, using the runner's child-command override. Its temporary helper invoked
`tools:up`, the existing selected endpoint test, and `tools:down` in one process tree. The helper
passed no credentials through arguments and printed only presence/validation results. Cleanup
stopped the test node and removed its Funnel mapping. No calls or AI/speech provider tests ran;
no new resource purchase succeeded during that initial check.

The initial restriction was cleared after the user created the Twilio Trust Hub compliance
profile. One subsequent `bin/livetests telephony:provision --allow-purchase` purchased the
machine's Twilio US local number and configured its fixed Voice route. A no-purchase repeat
reported all resources found for both carriers. No further purchase is needed. Do not treat
successful provisioning, REST authentication or key encoding as evidence of signed webhooks or
bidirectional call audio.

After successful provisioning, the ordinary `bin/livetests run --only live_telephony
apps/vxpipe_gateway/test/integration/public_telephony_endpoint_test.exs` also passed
**1 test, zero failures** (seed 771983). It used normal read-only carrier preflight and
automatic node/Funnel startup and cleanup; final tools status reported stopped.

The outgoing HTTP submission checkpoint passes focused local regressions: 69 engine,
50 Gateway, seven Calls and five PostgreSQL workflow tests. It orders durable start before
dialing, acknowledges accepted/unknown submission before room closure and deduplicates
client retries. All root gates passed: 3,104 tests, zero failures, 98 excluded, seed 755205;
Lean build/oracle/replay also passed. D6 then added durable outcome/timestamp projection and
passed all five root gates with 3,121 tests, zero failures, 98 excluded, seed 219668. Native
STS opening and the three bounded carrier acceptance calls remain open; provisioning and
these local tests do not prove carrier media or Telnyx callback-key matching.

The subsequent native turn-opening slice passed all root gates with 3,134 tests, zero
failures, 98 excluded, seed 269987, plus final Lean verification. The
[opening decision](native-sts-opening.md) records its provider-transcript validation and
bounded PCM assembly. Duplex opening and carrier acceptance remain open.

The subsequent duplex-opening checkpoint passes 161 focused regressions and all root
gates: 3,143 tests, zero failures, 98 excluded, seed 949782; Lean build/oracle/replay also
passes. Morse duplex generated/fixed opening and GPT-Live trusted greeting/verified fixed
burst are locally covered. This closes D3, with no hosted speech request or carrier call.
Fresh read-only discovery still finds both carriers' resources; a child-only boolean check
also confirms all six named settings plus Gemini/Deepgram keys present. Key presence does
not prove hosted speech authentication, and Telnyx callback-key matching and reciprocal
carrier audio still await E.

## E implementation and live evidence (2026-10-05)

Console now assembles encrypted carrier/speech credentials, opposing published routes,
production incoming/outgoing admission, archive projection, Deepgram Flux STT/TTS and bounded
Gemini 3.5 Flash Lite replies. Default tests use synthetic credentials and simulated carrier
or speech boundaries; the paid cases use the production adapters. Five local tests pass,
four live cases are excluded by default (seed 700659). The local incoming request exercises
the actual HTTP listener and waits for media while its durable call is `admitting`.

The pre-hangup-repair umbrella run reports **3,151 tests, zero failures, 103 excluded** (seed 930118).
Console's 200 default tests pass; its loopback HTTP case now belongs to the integration lane.
Earlier runs failed a busy-poll source-cutover wait and synthetic phone-transfer recovery
speech. Bounded state polling repairs the cutover observation. The recovery fixture now
acknowledges a streamed delta before its final response; both complete owning suites pass
in the umbrella run (1,881 Engine and 545 Gateway tests). Formatting, warnings-as-errors
compilation, strict Credo, unused-dependency and local documentation checks pass. Live carrier
acceptance remains separate from this default-suite result.

Select one case at a time:

```shell
bin/livetests run --only live_telephony_endpoint apps/vxpipe_console/test/integration/live_telephony_test.exs
bin/livetests run --only live_telephony_twilio apps/vxpipe_console/test/integration/live_telephony_test.exs
bin/livetests run --only live_telephony_telnyx apps/vxpipe_console/test/integration/live_telephony_test.exs
bin/livetests run --only live_telephony_unanswered apps/vxpipe_console/test/integration/live_telephony_test.exs
```

The endpoint case uses synthetic signatures and simulated carrier commands; it places no
carrier call. The other three cases can incur provider charges. Dial POSTs never retry.
Answered acceptance requires final transcripts on each **human** participant containing the
opposing distinct marker (`Alpha` or `Bravo`), then remote hangup, both room monitors and
durable archive closure. Each agent uses that marker as its fixed first message and its
only reply to other speech, so peer startup need not preserve the first utterance for the
audio proof. This proves reciprocal marker audio; native opening-once behavior is established
by the A–D local tests, not by assuming that the peer heard its first greeting.
Own-agent transcripts do not count. The unanswered case has no receiving publication and a
five-second ring bound. Cleanup is registered before submission and repeated in `after`.

The machine's local DNS resolves the `ts.net` origin privately, so a local HTTPS health check
does not establish internet reachability. The Console lane resolves public IPv4 records via
Google DNS over HTTPS, connects to a responding relay address and keeps the original hostname
for TLS/SNI and HTTP. Certificate verification remains enabled. A bounded public health check
must pass before any paid submission. Tailscale documents public DNS propagation delays in
its [Funnel troubleshooting](https://tailscale.com/docs/features/tailscale-funnel#dns-propagation).
The public synthetic test passed with the node kept online across readiness and test execution
(seed 217713). Immediate runs have also timed out before dialing; such failures are not carrier
acceptance evidence. Endpoint startup is still intermittently unavailable on public relays.

One selected Twilio → Telnyx call passed signed incoming admission and Telnyx answer, but
failed reciprocal audio transcripts (seed 778738). Twilio reported
[31924, WebSocket protocol error](https://www.twilio.com/docs/api/errors/31924); Telnyx delivery
records show accepted initiated/answered events and subsequent hangup/streaming stop.
The next selected call (seed 386272) verified the exact WSS Twilio signature and both HTTP
101 upgrades, accepted both carriers' start frames and received media on both sockets.
Local TTS then failed with `unsupported_audio`: the fixture requested 24 kHz while Gateway
output requires 48 kHz mono linear16. The fixture now requests 48 kHz; a test on its actual
Deepgram wire URL failed with 24000 before the change and passes with 48000. All five local
checks pass (seed 687328). Production signature and media validation remain unchanged.
With all three advertised IPv4 relays healthy for three consecutive probes, the next call
carried audio and produced final remote transcripts on both humans (seed 368816), but their
long greetings were interrupted and the required phrases were absent. Shortening the fixed
greetings yielded remote `Alpha` and reciprocal `acknowledged` transcripts (seed 142991),
while the outgoing human missed `Bravo`. Both agents now answer with their own short marker;
five local checks pass (seed 871247). These diagnostic calls do not establish either complete
answered acceptance case. The manual stabilization probe is bounded to ten minutes and
submits at most one selected call per case after all relays remain healthy.
The next Twilio call passed reciprocal markers (seed 327674), then exposed a test lookup
using a stale incoming record's nil incarnation ID. Room monitoring now obtains the exact
live identity through the public participant snapshot API; the local signed-incoming case
reproduced the failure and passes after the fix (five local checks, seed 54330). Console's
200 default tests also pass (seed 210099).

With that lookup repaired, the next selected Twilio call again passed reciprocal markers
and the outgoing room ended, but the incoming room did not end within ten seconds (seed
201787). At that attempt Gateway's incoming backend supported media start/data but returned
`telephony_event_not_supported` for terminal events. This identified the missing exact-incarnation
room termination path repaired in the final acceptance below.
The sequential parent stopped at that first failure, so the reverse and unanswered cases
were not dialed. The node and both test rooms were cleaned up.
At that point both answered cases and the unanswered gate remained open. The first unanswered selection
stopped at public health before dialing (seed 743241). A selected native Deepgram TTS probe
passed real audio/completion (seed 15667); read-only Deepgram and Gemini requests returned HTTP
200. These do not substitute for reciprocal carrier audio. Full evidence and diagnostic
limitations are in the [acceptance labnotes](../labnotes/20261005-0347-live-telephony-acceptance.md).

### Final live acceptance

The trusted Engine `end_call/3` operation and incoming Gateway terminal handling now close
only the activation's exact tenant/room/incarnation through normal supervision and archive
handoff. Twilio's authenticated bidirectional stop frame supplies its terminal event, with
strict account/call/stream matching. Telnyx uses its signed terminal webhook; stopping only
its media stream remains distinct from ending the call. See the
[incoming hangup decision](carrier-hangup-lifecycle.md).

| Selected case | Seed | Result |
| --- | --- | --- |
| Free public signed admission | 784537 | One test passed; no carrier dial |
| Twilio → Telnyx | 106192 | Reciprocal human marker transcripts; both room monitors DOWN; both durable archives closed; answered outcome and timestamps |
| Telnyx → Twilio | 662627 | The same reciprocal audio and natural closure evidence in the reversed direction |
| Unanswered Twilio → Telnyx | 247633 | One submission; `no_answer`; no answer timestamp; five-second ring bound plus its bounded margin |

Each selection passed one test with eight excluded. The parent kept the node online between
selections, dialed each case once and stopped the node afterwards; `tools:status` confirms it
is stopped. No personal phone, additional purchase or automatic retry was used. All six
named carrier/Tailscale credentials now have successful authentication evidence.

Public Funnel startup can temporarily close advertised relay connections. This acceptance
used bounded stabilization of all advertised IPv4 relays for three consecutive health probes
before the free admission test and paid cases. Immediate selected runs can still fail at
public health; this is an endpoint readiness limitation, not a missing credential. The harness
does not guarantee that the peer heard the very first marker utterance; fixed-opening once
semantics are verified locally, and ordinary marker replies make the remote audio proof robust.

Focused Engine lifecycle (19 tests), Gateway carrier/decoder/ingress (43 tests), and final
lifecycle/platform-tool (20 tests) checks pass, as do the three runner shell suites, formatting,
warnings-as-errors compilation, strict Credo, unused dependencies and Lean build/oracle/replay.
The repaired implementation's full umbrella gate passes **3,156 tests, zero failures, 103
excluded** (seed 930118). All required live gates and local completion checks are accepted.
Full evidence is in the
[final checkpoint labnotes](../labnotes/20261005-0927-carrier-hangup-lifecycle.md).

## Rejected alternatives

- **Dial a person's phone.** Requires an owned, approved destination per operator, a human to
  answer, and international rates for non-US operators. Self-calling removes all three.
- **Provision inside test setup.** Purchases, number reassignment and account mutation would
  become side effects of `mix test`, and concurrent runs would race on create-if-missing.
- **Funnel on the operator's own node.** Ties the URL to that machine's identity and risks
  clobbering the operator's own serve configuration.
- **Tailscale Services (`svc:`).** Gives a host-independent name, but Funnel support for
  Services is not documented; a separate node is documented and sufficient.
- **Cloudflare Tunnel or direct port exposure.** Needs a domain, DNS and certificate management;
  Funnel provides a trusted certificate on the tailnet name.
- **Reuse `APP_HOST`/`TELEPHONY_HOST`.** `config/runtime.exs` applies them to the whole test
  run, enabling the telephony listener for every test.
- **Twilio trial accounts.** Trial accounts can call only verified caller IDs and hold one
  number. The harness requires an upgraded (pay-as-you-go) Twilio account. Buying a number
  additionally requires an approved Trust Hub primary compliance profile (observed 2026-10-04:
  HTTP 401 "Primary compliance profile is not approved").

## Open questions verified during implementation

- Both carriers accepted the `ts.net` Funnel origin for real signed webhooks/media in the
  two completed acceptance calls.
- The accepted default uses hosted Deepgram speech and Gemini. Morse audio over live carrier
  transcoding remains an optional, unverified alternative; no extra paid call was made for it.
- Answering-machine detection is disabled in both test services. The successful cases verify
  that configuration, not how a carrier would classify the agents if detection were enabled.

## Sources

- [Tailscale OAuth clients](https://tailscale.com/kb/1215/oauth-clients)
- [Tailscale trust credentials](https://tailscale.com/docs/reference/trust-credentials)
- [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) and
  [`tailscale funnel` CLI](https://tailscale.com/kb/1311/tailscale-funnel)
- [Telnyx OpenAPI specification](https://github.com/team-telnyx/openapi) (paths and filters above)
- [Telnyx phone numbers guide](https://developers.telnyx.com/public/llms/numbers/global-phone-numbers-full.txt)
- [Twilio trial limitations](https://support.twilio.com/hc/en-us/articles/360036052753-Twilio-Free-Trial-Limitations)

## Twilio transfer acceptance continuation (2026-10-05)

The original [Twilio milestone](milestones/twilio-calls.md) also requires its private-transfer
runnable outcome and provider disconnect without blanket multiparty hangup. A–E initial-call
acceptance does not prove those requirements. The REST-only Gateway live cases do not observe
media, briefing, DTMF or bridge behavior. The active goal remains open for those checks.

The next fixture uses the existing owned numbers: Telnyx originates a caller to Twilio
reception; reception transfers to a second Twilio leg terminating at the owned Telnyx number.
A separate Telnyx receiving room simulates the destination. All three specs use the existing
participant/media schema and bound their lifetime to 90 seconds; the transfer attempt is
limited to 30 seconds. Transcripts are permitted, audio recording disabled, and wait sounds
disabled to keep the evidence focused on briefing and conversation.

The paid case must prove the remote destination hears the private briefing, sends real press-1,
then exchanges distinct speech with the caller through Vxpipe mixing. It must also terminate
only the destination leg, demonstrate the surviving caller/room, and close owned resources and
archives. Telnyx's [send DTMF](https://developers.telnyx.com/api-reference/call-commands/send-dtmf)
command sends tones to the opposite carrier; Twilio delivers them through its documented
[bidirectional-stream DTMF event](https://www.twilio.com/docs/voice/media-streams/websocket-messages#dtmf-message).
No fabricated normalized DTMF event can count as live acceptance.

The 2026-10-05 continuation was limited by the workspace sandbox: local TCP and Unix socket
binds, and PostgreSQL Unix-socket connections, fail with `eperm`. Mix also fails opening its
PubSub socket before the test suite starts. Pure fixture schema validation can run directly
under Elixir; this is narrower evidence and does not substitute for common Mix gates or live
acceptance. No further paid calls or purchases were attempted during that blocked session. Detailed checkpoint evidence
is in the [continuation labnotes](../labnotes/20261005-2227-twilio-live-transfer.md).

The selected transfer lane was prepared during that blocked session and is now live-verified
by the 2026-10-06 acceptance recorded below:

```shell
bin/livetests run --only live_telephony_transfer apps/vxpipe_console/test/integration/live_telephony_test.exs
```

It uses real carriers and Deepgram STT/TTS, with a local deterministic model fixture for
opposing Alpha/Bravo markers and one reception transfer request. This avoids extra hosted
LLM charges and cannot request a second transfer after failure. The earlier initial-call
cases retain their real Gemini inference. The transfer case makes at most two carrier dials
and bounds each room to 90 seconds and the transfer attempt to 30 seconds.

The implemented assertions require destination recognition of a unique private briefing marker
(Delta or check), neither marker at the caller, real peer press-1, destination main admission and
reciprocal post-bridge speech. They also require one completed transfer and three call records,
then exact destination hangup with surviving caller/reception and final closure of all three
archives. Negative transcript evidence is bounded; exact privacy/frame isolation remains
covered by the local signed harness. No synthetic callback or DTMF Event substitutes for a
carrier event in this case.

Eleven local component tests pass (seed 466420), covering publication/source contracts, private
binding lookup, peer command encoding and failure handling, and the one-shot model. The live
module compiles directly without warnings; formatting passes. Those checks do not establish
assembled database execution or live carrier acceptance. Remaining common gates and the
selected carrier run still required local socket/DB access unavailable during that session.

The first implementation proposed one six-character Bravo marker after main admission using
Telnyx's [basic speak command](https://developers.telnyx.com/api-reference/call-commands/speak-text).
The payload explicitly selects basic service, English, one loop and only the peer's own leg.
This acts as a controlled handset stimulus; it does not add a Telnyx TTS application provider.
Its provider charges are part of the selected live case, alongside the two calls and Deepgram
speech. This avoids depending on an idle timer after both greetings finished privately.
Before press-1 the case also requires no destination Bravo at the caller and no caller Alpha
at the destination. Post-bridge reciprocal speech remains required. No speak command has
been sent to a real carrier during that blocked continuation. That stimulus was subsequently
attempted and replaced as recorded below.

### Resumed execution (2026-10-06)

Socket, database and outbound HTTPS permissions now work. Normal Console checks pass 15 tests
(six selected live cases excluded, seed 954488), including encrypted database execution. The
first selected transfer run published all three encrypted specs and reached actual caller and
destination carrier media, then failed before remotely heard private briefing (seed 26764).
The destination's early audio arrived while every private input route was unallocated; Gateway
incorrectly interpreted intentional silence as unavailable media and closed the socket.

A focused regression reproduced that failure before implementation (seed 294130). Gateway now
drops those packets only during private preparation when every input route is disabled. It
still fails on actual input errors and on main attachments with no usable route. The regression
and two-carrier signed conformance group pass 49 tests (seed 302441). The selected carrier case
is being rerun after that change; press-1, post-bridge audio and selective hangup remain pending.
No new resources were purchased. See [resumption labnotes](../labnotes/20261006-0206-resume-live-transfer.md).

Subsequent selected runs kept media connected and reported successful private playback.
The recognizer returned different portions of the briefing: Delta in some runs and the notice's
check marker in others. The test therefore accepts either known unique marker and requires both
absent at the caller. No caller, reception or destination model can generate either word outside
the briefing. This proves remote private audio without requiring a complete literal transcript.
The readiness observation now allows 15 seconds for playback and provider cleanup, while the
application's total transfer deadline remains 30 seconds. No synthetic DTMF or readiness signal
is injected. Both bridge directions and selective lifecycle cleanup remain required.

The actual Twilio press-1 frame uses `inbound` in this account, whereas the
[documented DTMF example](https://www.twilio.com/docs/voice/media-streams/websocket-messages#dtmf-message)
uses `inbound_track`. The decoder accepts both equivalent inbound labels and continues rejecting
outbound/unknown tracks and mismatched streams. A focused red-green decoder test and the signed
two-carrier group pass 50 tests (seed 803124); a selected carrier run confirms the real label,
acceptance and completed human transfer (seed 245942). The bridge speech check still failed,
so selective hangup acceptance remains pending.

The accepted Telnyx native-speak request did not establish remotely recognized bridge speech.
The final fixture instead holds the destination's model response until the test observes main
admission, then releases Bravo through Vxpipe's ordinary real Deepgram TTS pipeline. The local
fixture model gate has a bounded wait; it cannot accept a transfer or alter media admission.
The native-speak helper is removed, avoiding an extra carrier speech command and its charge.
An opposing caller response must still cross both physical carrier calls and Vxpipe's human
bridge before the existing reciprocal-transcript assertion can pass.

The gated application TTS run recognized Bravo at the caller through the accepted bridge, but
still lacked Alpha at the destination (seed 637789). Public mixer counters exposed large
timestamp-buffer overflow without policy drops or sink overflow. The configured 300 ms playout
delay exceeded the buffer's eight 20 ms timestamps (160 ms), so ordinary steady-rate audio
overflowed before becoming due. A focused configured-runtime test failed first (seed 228169).
The bounded default now holds 32 timestamps (640 ms), retaining the 300 ms delay with jitter
margin. Reducing the playout delay would alter established timing and is unnecessary to repair
the inconsistent capacity. Mixer/policy/human-phone tests pass 36 cases (seed 486056), and the
two-carrier conformance group passes 50 (seed 655566). Reciprocal live acceptance is pending the
selected rerun with that configuration, whose result is recorded below.

### Accepted real transfer (2026-10-06)

The final selected transfer case passes **one test, zero failures, nine excluded**, seed 918113
(31.2 seconds). The destination hears a private briefing marker, real Telnyx press-1 arrives as
Twilio's `inbound` DTMF frame, one transfer completes, and remotely recognized Alpha/Bravo
cross the accepted human bridge in both directions. Private markers remain absent at the caller.
Exact destination hangup ends only its room and the corresponding transfer leg/media, retaining
caller/reception; final reception stop ends the opposing caller. All three durable call records
and permitted transcript archives close. `tools:status` reports the node stopped.

Ten selected transfer attempts were needed to resolve the integration and probe issues above;
each was bounded to one caller dial and one transfer dial, with no automatic redial. No other live
provider lanes ran during this resumption and no resources were purchased. The final probe uses
real Deepgram speech with a local one-shot model and a bounded post-admission destination gate.
It does not inject carrier events, bypass admission, or save audio. The earlier Gemini-backed
initial-call acceptance remains separate evidence. Audio markers do not establish arbitrary
speech quality, latency guarantees, or first-utterance reception.

Final common verification after the accepted transfer passes formatting, warnings-as-errors
compilation, strict Credo, unused-dependency checks and **3,171 default tests, zero failures,
104 excluded** (seed 235060). Lean build/oracle/replay pass (replay seed 497321); all three runner
shell suites pass. Final focused speech/persistence checks pass 74 tests at the same seed after
correcting three test synchronization races. The Twilio milestone and its index entry are complete.
An intermittent local WebRTC third-participant tone observation remains documented with an
unproven cause in the [resumption labnote](../labnotes/20261006-0206-resume-live-transfer.md);
its original assertions passed in both subsequent full Gateway runs without production changes.
