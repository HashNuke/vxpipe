# Telephony provisioning check

The user requested completing real telephony provisioning before further outgoing-call work.
Used `bin/livetests` exclusively for credential loading. Never read or modified the live env
file, printed credential values, or passed secrets through argv.

- Read-only status: Telnyx machine-named outbound profile, Voice API application and assigned
  number exist. Twilio machine-named number is missing.
- One authorized purchase attempt: Telnyx resources reused; Twilio purchase failed with HTTP
  401, primary compliance profile not approved. No new purchase succeeded. No test call placed.
- Child-only temporary preflight: all six requested settings present; Tailscale OAuth client
  credentials accepted by `/api/v2/oauth/token`; access token discarded in memory. Telnyx
  public key decodes as 32-byte Ed25519 material. Real account/signature match remains open.
- The temporary helper initially hung capturing `tools:up` stderr because tailscaled inherited
  progress fd 3. Process inspection confirmed the helper/node were running. Stopped that helper
  and the test node explicitly. Replaced pipe capture with a temporary stdout file, then reran.
- Production Gateway public endpoint test: 1 test, zero failures, seed 530653. Invoked through
  a temporary child-command override so missing carrier resources did not block this independent
  endpoint check. Both node and Funnel stopped afterward.
- Verified Tailscale client credentials flow against the official OAuth-client documentation:
  https://tailscale.com/docs/features/oauth-clients . No resources were created through that API.

The blocker is account compliance, not absent named settings. Twilio REST discovery and number
availability authenticated successfully. Do not repeat purchases until the user's Trust Hub
primary compliance profile is approved. Then rerun provision with `--allow-purchase` and a
find-only pass to establish idempotency. Live audio/callback evidence still awaits D and E.

Updated milestone, index and harness record without marking real provisioning complete.
Sent progress updates using pushnotify. No runtime code or dependency changed in this check;
only the selected network endpoint test was needed, not the full paid provider suite.

## Restriction cleared

The user subsequently reported creating a Twilio compliance profile. One authorized provisioning
retry succeeded: it reused the three Telnyx resources, bought the missing Twilio US local number,
set its fixed Voice URL and reported both providers ready. A subsequent provisioning run without
purchase permission reported all resources found and succeeded. All resource names/tags belong
to `vxp-test-rocksalt`; no account-wide settings or unrelated resources were changed.

The ordinary runner, with normal carrier preflight and no helper override, then passed the
public Gateway endpoint test: 1 test, zero failures, seed 771983. `tools:status` afterward reports
the node stopped. No calls were placed. Updated the milestone/harness to clear the historical
blocker; real signature matching and two-way audio remain E's acceptance work.
