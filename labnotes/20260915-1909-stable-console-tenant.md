# Stable Console tenant

## Checkpoint

Console sample setup now selects an existing tenant with `VXPIPE_DEV_TENANT` instead of
creating a new tenant on each BEAM restart. It saves and publishes the definition first,
resolves its participant routes, then issues a call-scoped API key. That key stays in the
supervised server process. Failed definition setup does not issue keys or create tenants.
An absent or blank selector disables the managed development sample.

Bootstrap the tenant with the trusted operator workflow in `docs/tenant-control-plane.md`,
then set its public key in the optional `VXPIPE_DEV_TENANT` entry in visible `env.sample`.
This extracted checkpoint changes sample ownership only. The inline provider/credential
runtime cutover remains in the subsequent checkpoint.

## Evidence

- Changed sample tests initially failed 6 tests/5 failures, seed 276648. After implementation,
  sample, endpoint, provider-runtime and storage tests passed 24/0, seed 633006.
- Extracted the sample implementation/tests and only the tenant-selector configuration and
  documentation hunks into an isolated checkout of `5203ca0`. Sample and endpoint tests passed
  **16 tests, 0 failures**, seed 997844, without depending on the pending inline-schema changes.
- Browser acceptance on the combined working tree used a disposable DB, random platform keyring
  and synthetic provider credentials. Chrome at 1440×960 and 390×844 rendered the sample without
  clipping. Calls prepared before/after BEAM restart; the same one tenant and two credential
  bindings remained. Response inspection found public locators/join token and no provider marker.
  The browser did not join a live provider call. Closed the owned browser/server and dropped the DB.
- Root formatting, warnings-as-errors compilation and strict Credo passed.
  Dependency declarations and lockfiles are unchanged. Full umbrella completion checks follow
  with the consuming inline-schema checkpoint.
