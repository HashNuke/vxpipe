# Consent asset versioning

## Cause and decision

The user clarified that Allow opens a second tab while the original remains at
Saving your choice. That matches the removed popup implementation, including its
extra presentation field; the current bundle has neither behavior. The live
server's `unexpected_form_fields` rejection is consistent with that old form.
Public asset bytes match the current build, but consent HTML still used the same
unversioned script URL across deployments. The exact browser cache mechanism was
not observed directly.

Use Phoenix's existing asset fingerprinting so a newly loaded consent page names
its deployment's bundle. Add `phx.digest` to production asset builds, configure
the endpoint manifest in production, and resolve the consent page's JavaScript
and both stylesheets with `Endpoint.static_path/1`. Generated files remain
ignored. No compatibility branch or old popup behavior is restored. Existing
consent tabs must be replaced with a fresh client authorization attempt.

## Verification

- Red: the focused Console integration case failed because the rendered page
  ignored the endpoint's versioned asset paths. Green: all 17 OAuth browser cases
  pass. This checks our template wiring, not Phoenix's hashing implementation.
- Root format, warnings-as-errors compilation, strict Credo and unused dependency
  checks pass. No full suite was run. The normal production assets build passes
  its TypeScript check, CSS/JavaScript compilation and Phoenix digest generation.
- Real Chrome with the old `/assets/oauth.js` URL explicitly blocked loads the
  fingerprinted bundle. The form has no removed presentation field or tab target.
  Desktop CIMD approval and mobile DCR denial both show confirmation in the same
  tab, with Back to my app and no stuck Saving state. One tab remains. Screenshots
  were inspected. The test uses synthetic users in a rollback-only database.
- The temporary browser session and fixture server were stopped after checking.
  No environment files were read.

## Release

- Deployed the rebuilt QA release. Both services are active and public health
  returns ok. The container remains at 1 GiB. Running image:
  `sha256:b556fd1c4d4ffa3ecab380445919e5eb5f715a097adc802915d106ecad77af58`.
- A synthetic unknown-client request exercises the deployed consent renderer
  without issuing a grant. The resulting HTML references the exact three
  fingerprinted paths in the build manifest, and all three publicly served files
  match the built bytes. The first probe used a noncanonical synthetic PKCE
  challenge and stopped at input validation; corrected it before verifying HTML.
- The deployed script is `/assets/oauth-d3f03fdbf2a5cc4863337686acc2f687.js?vsn=d`,
  a new URL independent of the browser's cached `/assets/oauth.js` response.
  Existing open tabs still need replacing because already-executing JavaScript
  cannot be replaced by a server deployment.
