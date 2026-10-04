# Outgoing calls and live telephony tests: specification

## Goal

Specify outgoing calls from a saved call spec and a live telephony harness that needs no personal
phone number, per the user's 2026-10-02/03 decisions: Vxpipe calls its own US numbers, a
per-machine Tailscale node `vxp-test-<machine>` with tag `tag:vxp-test` provides the public
endpoint, and `bin/livetests` (`run`, `tools:*`, `telephony:*`) replaces `bin/test-live-providers`.

## Internal findings

- `Vxpipe.CallEngine.CallSpec.ConnectionIntent` supports `mode: dial` only with
  `admission: transfer`; outgoing entry calls need `dial` + `start_call`.
- `entry_caller` must be a human participant; for an outgoing call it is the dialed human.
- `POST /api/tenants/:tenant/participants/:participant/calls` prepares a web call through
  `Vxpipe.Calls.Admissions.prepare/4`, which resolves a published participant route and checks it
  matches `entry_caller`. The outgoing API reuses this preparation path.
- Outbound legs exist for transfers (`OutgoingLegConnector`, `OutboundLegRequestResolver`,
  outgoing leg owners) and resolve service references freshly before dialing.
- R39 rejected an API creation idempotency key; the spec flags this for review because outgoing
  requests place paid calls.
- Database-backed tests use `VXPIPE_TEST_DATABASE_URL`, e.g.
  `postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test` (from the Twilio milestone evidence).

## External findings

- Tailscale: OAuth client secret works as `tailscale up --auth-key` with mandatory
  `--advertise-tags`; defaults `ephemeral=true`, `preauthorized=false`. Funnel ports are
  443/8443/10000. Default Funnel nodeAttr targets `autogroup:member`, so tagged nodes need their
  own. Creating an OAuth client with a tag appears to require the tag in `tagOwners`
  (tailscale/tailscale#20489). Funnel with Tailscale Services is undocumented.
- rocksalt (read-only): `rocksalt.tail445590.ts.net`, Funnel capability on 443/8443/10000,
  operator `malt`, no serve configuration.
- Telnyx OpenAPI: `/phone_numbers` filters include `tag`, `connection_id`,
  `customer_reference`; PATCH accepts `tags`, `connection_id`; `/number_orders` accepts
  `connection_id`, `customer_reference`; call control applications filter by
  `application_name` and carry `webhook_event_url` and `outbound.outbound_voice_profile_id`;
  outbound voice profiles filter by name and carry `whitelisted_destinations`. No API returns
  the webhook public key.
- Twilio: trial accounts call only verified caller IDs and hold one number, so the harness
  requires an upgraded account. Webhook signatures cover the exact URL including any port;
  using Funnel port 443 avoids port handling inconsistencies.

## Decisions

Recorded in `docs/live-telephony-harness.md` with rejected alternatives; checkpoints in
`docs/milestones/outgoing-calls-and-live-telephony.md` (index entry 37).

## Status

Specification review pending. Checkpoint A (runner rename) implemented; see below.

## Checkpoint A: `bin/livetests run`

- Red: renamed `test/shell/live_provider_runner_test.sh` to `test/shell/livetests_test.sh`,
  pointed it at `bin/livetests run`, and added help/usage/removal checks; it failed with
  `bin/livetests: No such file or directory`.
- Green: `git mv bin/test-live-providers bin/livetests`, wrapped the existing behavior in `run`,
  added `help` and exit-2 usage errors, and added `TAILSCALE_CLIENT_ID`/`TAILSCALE_CLIENT_SECRET`
  to the isolated credential names. The user chose those names (2026-10-04); only the secret is
  needed for registration because the OAuth client has only the Auth Keys write scope.
- `shellcheck` is not installed here; `bash -n` passes.
- No Elixir code changed, so the mix gates were not rerun for this checkpoint.
- The user's Twilio account is upgraded (not trial), so the two-call design is not blocked.
