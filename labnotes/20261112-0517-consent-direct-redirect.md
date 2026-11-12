# Consent direct redirect

## Decision

The user requested automatic return to the client after consent so a successful
approval cannot be stranded behind a second button. Use the existing native POST
and send HTTP 303 to the validated callback after approval or denial. The browser
follows with GET, including without JavaScript, following
[RFC 9700 section 4.12](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.12).
Keep exact callback/query, state/issuer, current authority, CSRF, one-time use and
private/no-store/no-referrer contracts. Missing or unsafe callbacks fail locally.

Remove the superseded confirmation components/bootstrap, unused styles and
transaction receipt payload instead of retaining a second completion path.
Storybook's decision flow now goes directly to its simulated client; the handbook
and current milestone contracts describe the same behavior.

## Verification

- Red: three focused Console failures establish the old 200 confirmation and
  missing-callback exception; two Storybook-flow cases establish the extra action.
- Green: 17 Console boundary cases, 10 persistence cases and 12 UI cases pass.
  They cover exact redirect data, 303, CSRF, missing/unsafe callback failures,
  expiry, authority, grant creation and replay protection. No full suite ran.
- Root format, warnings-as-errors compilation, strict Credo, unused dependencies,
  changed-file ESLint and the production TypeScript/assets build pass.
- Real Chrome CIMD and DCR approval/denial return directly in the same tab and
  preserve the initiating client's opener. Both approval flows complete S256
  exchange, MCP initialize/catalog/tool use, refresh/session reuse and revocation;
  revoked requests and code replay fail as expected. Desktop/mobile consent and
  action layout were inspected with synthetic rollback-only database fixtures.
- With JavaScript disabled via Chrome DevTools, the native form still returns to
  the client and completes code exchange. An unreachable loopback callback leaves
  its exact destination and code/state/issuer in browser navigation history,
  suitable for copying into a manual-login CLI; no callback values were printed.
- One documentation/CSS edit command used the child-app working directory and
  failed before editing. It was corrected using absolute paths. A log read also
  used the wrong directory; test results were read from their actual root logs.
- No environment files were read and no new dependencies were introduced.

## Release

Deployed the rebuilt QA release to Vitrum. Public fingerprinted OAuth JavaScript
and CSS match the verified build; health returns ok and both system services are
active. The container retains its 1 GiB limit. Temporary browser and rollback-only
fixture processes were stopped. The milestone and index are synchronized.
