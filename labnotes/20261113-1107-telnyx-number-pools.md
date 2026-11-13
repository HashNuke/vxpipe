# Telnyx number pools

## Request and decision

Reuse owned test numbers before purchasing. Tags describe shared and machine
pools; caller/receiver roles are private local profile data rather than unique
carrier tags. Work is on `qa`.

- Preserve valid existing application assignments and saved roles.
- Fill the two-number requirement with active, unassigned
  `vxpipe-test-<machine>` numbers, then `vxpipe-test` numbers. Deduplicate by
  number ID and purchase only the remaining shortage with `--allow-purchase`.
- Keep the existing `vxp-test-<machine>` application/profile/Tailscale names.
- Save application/caller/receiver IDs atomically in a mode-600 local JSON
  profile under the existing machine state directory. Never store credentials
  in this profile. Missing/stale local state is reconstructed from current
  carrier assignments; valid receiver roles survive caller replacement.
- Shared-pool reuse moves the machine tag while preserving unrelated tags.
  Cleanup selects the current machine tag, never the shared tag by itself.
- Status and test-run discovery are read-only. Provisioning rechecks assignment
  immediately before patching a candidate. This detects observed ownership
  changes; the Telnyx GET/PATCH sequence is not an atomic cross-machine lease.

Telnyx's [official SDK phone-number model](https://github.com/team-telnyx/telnyx-node/blob/master/src/resources/phone-numbers/phone-numbers.ts)
defines tags as a list and connection IDs as nullable. Both pool tags were also
confirmed by GET after updating the existing resources.

## Design review

Checked selection order, overlapping pool membership, partial shortages, stale
local roles, read-only discovery, and cleanup ownership before implementation.
Rejected role-specific tags and a distributed allocator: a local role mapping
and bounded carrier provisioning are sufficient for this test harness. The
milestone's tooling contract and development guide now describe the same rules.

## Implementation and evidence

- Extracted Telnyx number discovery/allocation into one shell helper. Inventory
  is paginated; application and Twilio provisioning retain their existing flow.
- Red: the focused provisioning fixture failed with `did not reuse machine and
  shared pools` before implementation.
- Red: a released number with another machine's tag exposed stale machine
  ownership; its tag is now moved when allocated from the shared pool.
- Green: offline provisioning fixtures cover mixed pools, machine-first order,
  exact allocation count, inactive/busy/untagged exclusions, pagination,
  overlapping tags, preserved unrelated tags, stable/rebuilt local roles,
  assignment changes during discovery, and buying only a shortage with consent.
- Green: offline cleanup fixtures verify exact machine tagging and preserve
  unrelated/shared-only numbers. Existing export, optional Twilio, repeat-run,
  and carrier-failure checks also pass.
- `bash -n` and `git diff --check` pass. No Elixir code changed; no umbrella
  suite or live telephony tests were run. The shell fixtures replace both
  carrier HTTP clients and Mix with local fakes.

## Existing resource update

Used the running application's stored credential in memory; did not open any
user environment files. Changed only tags on the two numbers already assigned
to the machine's Voice API application. Both now have `vxpipe-test` and
`vxpipe-test-rocksalt`; the old role tags were removed. Follow-up GETs verified
both tag sets and unchanged application assignments. Seeded the local profile
with the existing caller/receiver roles without printing credential values or
committing resource IDs. No calls, number orders, app/webhook changes, or
deployments were performed.
