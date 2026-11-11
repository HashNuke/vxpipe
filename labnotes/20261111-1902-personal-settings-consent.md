# Personal settings and consent

## Scope and order

Implement the reviewed QA Storybooks through the personal-settings/MCP-consent
milestone. Stay on `qa`; preserve main and unrelated work. The memory
investigation prerequisite is complete in `71a0a716`. The user explicitly
requested focused tests only, overriding the milestone's full-suite instruction.
No environment files were read. Existing checkout setup/dependencies were reused.

## Personal settings

- Promote the shared Settings → For you sidebar and remove its preview flag.
  Settings remains available when there are no administrative destinations.
- Wire `/account/connections` through the authenticated server and React routes,
  using the existing session-bound list/revoke API and confirmation component.
  Account editing remains separate and retains the self-account write endpoint.
- Red: five production routing/session cases, three sidebar cases and the
  server deep-link case failed before implementation. Green: personal pages
  work for Superadmins, Admins, members and users with no grants/assignments.
- Keep connection ownership in Persistence. Expanded the real two-user check
  to preserve another grant for the same user/client and the other user's grant,
  while rejecting access-token authentication and refresh after selected revoke.
  Nine Persistence cases and 33 Console routing/OAuth cases passed.
- The frontend state checks cover retained rows after failure, cancellation,
  focus return, pending/duplicate confirmation, session expiry and success focus.
  An Escape test initially dispatched on document rather than the focused
  dialog; corrected the event target without changing the working component.
- A real-browser check uses an ignored loopback server with real identity and
  OAuth repositories in a rollback-only sandbox transaction. Synthetic member
  accounts have no grants or memberships. No production account was modified.
  Desktop 1440 and mobile 390 render correctly; cancellation preserves both
  grants, successful revoke removes only the selected grant after reload, and
  the mobile drawer selects the separate account page correctly.
- Browser testing found an existing wrong-current-password issue: the endpoint
  returned 401, so the navigation fetch wrapper treated the failure as session
  expiry. An initial frontend-only distinction was insufficient because the
  outer wrapper invalidated the workspace first. Chose the smaller boundary
  correction: return 422 `invalid_current_password` for this validation failure,
  keeping 401 for invalid browser sessions. Added red endpoint and form/retry
  cases before the correction. The form reports a specific error and preserves
  the edited email. Ordinary login error semantics stay unchanged.

## Personal-settings verification

- The final account/API selection passed 41 frontend tests, including the
  wrong-password retry and ordinary expired-session/password-sign-out cases.
  Other focused navigation, connections and Storybook journey selections passed;
  the corrected five-case confirmation file passed independently. TypeScript and
  changed-file ESLint passed.
- Console authentication/authorization selection passed 41 tests (eight excluded
  by the file/line selection), including actual-database password sign-out and
  grant-bound MCP session rejection after persisted revocation. The self-account
  endpoint also passed with an attempted foreign `user_id` ignored in favor of
  the authenticated principal. Thirty-three routing/OAuth and nine Persistence
  cases passed earlier in this checkpoint.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed. Assets and Storybook production builds passed. Storybook was
  built from a disposable tracked-source copy excluding all environment files,
  because the normal configuration calls Vite's environment-file loader.
- Final Chrome check confirmed the corrected password error stays on `/account`,
  retains the edited email and permits retry; an email-only edit survives reload
  without sign-out, while a password change shows the sign-out notice. A second
  real user sees their own empty connection list and administrative sidebar.
  Storybook light/mobile and failed-revoke states also render correctly without
  horizontal overflow or browser exceptions. The loopback test server was stopped,
  rolling back its users/grants. Waits initially matched a login password field or
  a hidden mobile rail; used the actual page state to confirm final observations.
- Source/code on QA is verified; the running release has not yet been rebuilt for
  this checkpoint. Deployment follows the completed consent work.

## Remaining checkpoints

Implement optional CIMD/DCR branding and the shared reviewed consent presentation.
Record the OAuth completion/callback transport decision before changing redirects;
approval must not be presented as a completed client token exchange.

## Branding and production consent

- Red: standard branding was rejected/dropped (two Identity and three Persistence
  failures); the actual server renderer lacked the shared UI entry (one Console
  failure). Added shared presentation tests before implementation. New optional
  HTTPS metadata now survives CIMD/DCR validation, storage and consent DTOs.
- URLs are bounded using the existing URL boundary, reject embedded credentials,
  and cannot inject active schemes. Old missing/unsafe optional metadata is
  omitted from presentation. The existing metadata digest includes branding;
  a logo-only refresh rejects approval of the prior displayed request. No schema
  migration, network proxy or new dependency was added.
- Extracted the reviewed React presentation into `OAuthConsent`, used by the real
  page and Storybook. The backend supplies the user email, actual permission and
  tenant ceiling, and the same grant duration used when storing grants. Kept
  the approved permission descriptions and layout. A browser check exposed raw
  reserved user permission keys in headings; a focused red test drove readable
  labels while retaining exact keys in Connection details.
- The production form remains an ordinary authenticated POST with CSRF and the
  chosen decision. It does not intercept the callback. A no-JavaScript native
  form remains available with the same authority and exact client/callback data.
  The reviewed outcome screens still belong to the Storybook flow.
- Green: 10 Identity, 18 Persistence, 13 Console, 10 shared UI/Storybook tests;
  TypeScript, changed-file ESLint, assets/Storybook builds and root format,
  warnings-as-errors compilation, Credo and unused-dependency checks pass.
  No full suite was run.
- Real Chrome validation used synthetic users in a rollback-only test database
  and separate loopback Vxpipe/client HTTP listeners. Both CIMD and DCR delivered
  code/state/issuer to the original client window, exchanged S256 codes, initialized
  MCP, listed tools, invoked `list_tenants`, refreshed and retained the MCP session,
  then rejected access after revocation (401) and code replay (400). Denial for
  both delivered `access_denied` with original state/issuer. The CIMD peer uses
  the existing DNS/HTTP test adapter seam to serve local metadata; this does not
  bypass production validation or claim a third-party interoperability run.
- Desktop 1440, mobile 390, actual no-permission member and Superadmin consent,
  missing/broken logos and Storybook light mode were inspected. No horizontal
  overflow or JavaScript exceptions observed. One browser wait used an unsupported
  text-selector form; the callback had already succeeded. The temporary peer's
  unhandled favicon requests did not affect any protocol checks.
- Completion UX is the remaining decision. Asked whether to retain the original
  tab callback with a separate Vxpipe receipt, or keep one tab with direct return.
  No answer yet. Replacing the callback with a receipt breaks delivery; moving
  the callback into another window can break client opener assumptions. Kept the
  compatible original-window 302 and have not introduced receipt infrastructure.
