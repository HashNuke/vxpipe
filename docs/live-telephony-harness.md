# Live telephony harness

Status: proposed 2026-10-03; research recorded, implementation not started. Implementation is
tracked by [Outgoing calls and two-call live telephony](milestones/outgoing-calls-and-live-telephony.md).

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
- The node persists its identity in its state directory; later runs reconnect without the secret.
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

Tests then check carrier state read-only before dialing and fail with an explicit message, for
example that the tagged number is not assigned to the machine's application.

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
  number. The harness requires an upgraded (pay-as-you-go) Twilio account.

## Open questions verified during implementation

- Whether Twilio and Telnyx accept the `ts.net` Funnel origin for webhooks and `wss://` media.
- Whether deterministic Morse audio survives carrier transcoding well enough to serve as the
  default no-cost speech for the two-call test, or whether the default test needs real STT/TTS.
- Whether answering-machine detection must be disabled for agent-to-agent test calls (expected:
  yes, because an instant synthetic answer can classify as a machine).

## Sources

- [Tailscale OAuth clients](https://tailscale.com/kb/1215/oauth-clients)
- [Tailscale trust credentials](https://tailscale.com/docs/reference/trust-credentials)
- [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) and
  [`tailscale funnel` CLI](https://tailscale.com/kb/1311/tailscale-funnel)
- [Telnyx OpenAPI specification](https://github.com/team-telnyx/openapi) (paths and filters above)
- [Telnyx phone numbers guide](https://developers.telnyx.com/public/llms/numbers/global-phone-numbers-full.txt)
- [Twilio trial limitations](https://support.twilio.com/hc/en-us/articles/360036052753-Twilio-Free-Trial-Limitations)
