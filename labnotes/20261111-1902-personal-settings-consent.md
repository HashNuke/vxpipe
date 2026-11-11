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

## Checkpoint sequence

Personal settings precede branding and shared consent. Record the OAuth
completion/callback transport decision before changing redirects; approval must
not be presented as a completed client token exchange.

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

## QA release checkpoint

- Pushed personal settings as `dff7f912` and branding/shared consent as `a85f1991`
  on `qa`. Main was not modified. The final Storybook build also passes after the
  shared stylesheet rename; the final focused UI selection passes ten cases.
- Built production assets and the OTP release from QA, rebuilt `vxpipe:local`
  using only the assembled release context, and restarted `vxpipe.service`.
  No environment file was read. Existing systemd runtime configuration remains
  responsible for supplying the application's environment.
- Vitrum health returns `ok`; both Vxpipe and Caddy system services are active.
  Public `admin.js`, `oauth.js` and `oauth.css` hashes match the assembled release.
  The public login page renders in Chrome. A Python HTTP fetch returned 403;
  ordinary curl and Chrome succeeded, so the deployment check used those clients.
- Running image: `sha256:02a642537529181ca1240f8b91e7633bda2af47a5e9f79cb6a25b706094e51ff`.
  Container limit remains 1 GiB, observed usage about 322 MiB after restart.
  The rollback-only browser VM and temporary Storybook server were stopped.
- This deploy includes personal settings, connection revocation and production
  consent branding. It does not claim the pending completion receipts are live.

## Request-failure recovery

- Continued the independent failure-screen work while the callback/receipt choice
  remains unanswered. Failed authorization requests previously returned plain
  text, despite the reviewed unavailable-request design.
- Red: two Console cases and the new Storybook recovery-link case failed. Shared
  `OAuthUnavailable` now renders production failures and the preview. It receives
  no client identity or authority when backend validation fails. The original
  400/403/503 status, private/no-store response and absent callback are preserved;
  no approval or token-exchange success is implied. A no-JavaScript recovery link
  remains available. Kept the reviewed layout and 44-pixel action height.
- Green: 14 focused Console and 11 shared consent/Storybook tests. TypeScript,
  changed-file ESLint, production assets, Storybook build, root format,
  warnings-as-errors compilation, Credo and unused-dependency checks passed.
  Existing Persistence cases already verify that expiry and changed authority
  produce the invalid-request boundary handled by this page.
- In the actual rollback-only browser flow, deny returned to the local client;
  revisiting and reloading the consumed request rendered the recovery screen.
  Desktop 1440 and mobile 390 showed no overflow or authorization controls.
  Back to Vxpipe reached Console home and its correct No tenant access state for
  the member without memberships. Storybook uses the same recovery component.
  Browser errors were empty. Corrected two inspection selectors after their
  waits timed out: the app uses navigation-layout, and the story is named
  Request Unavailable. These were inspection mistakes, not application failures.
- Approval/decline receipt transport remains the only implementation decision
  awaiting the user's choice. No popup/callback behavior was added in this slice.

- Recovery release deployed to Vitrum. Public OAuth JavaScript/CSS match the
  release artifacts; a browser request for an unregistered synthetic client
  renders the recovery page without signing in or creating a grant. Both services
  remain active, health is `ok`, and the container limit is unchanged at 1 GiB.

## Completion decision and implementation

- The earlier question was an optional UX preference, not an authorization gate.
  Continued with its separate-receipt default after the independent work, rather
  than leaving the requested outcomes unfinished. This is an implementation
  assumption, not a claim of explicit user confirmation. Consent announces the
  extra tab; the reviewed outcome layout and primary/secondary actions remain.
- A decision gesture reserves a named receipt window and submits the native form
  into it. The browser-only `presentation=receipt` field is closed and validated.
  Blocked/detached windows and JavaScript-free submissions keep the ordinary 302.
  Duplicate UI submissions are suppressed; one-time database consumption remains
  the authority. There is no receipt table, queue, cookie or postMessage protocol.
- Persistence returns presentation, snapshot and persisted grant expiry from the
  same transaction that checks the current session/authority, locks client
  metadata, creates the grant or denies, and consumes the request. It does not
  rebind consent before completing. Denial creates no grant and preserves others.
- Receipt delivery checks the opener's origin and exact opaque request path,
  severs its own opener, then redirects the original window. Missing/closed or
  unrelated openers fall back to current-window callback delivery. Callback data
  is removed from bootstrap attributes and never placed in another Vxpipe URL or
  browser storage. Approval means permission was recorded, not that the client
  exchanged its code. The receipt displays the actual stored expiry.
- Red: two Persistence receipt assertions, one Console receipt-response case and
  the new browser transport contract failed before implementation; a detached
  window case later failed before adding the available-window check. Green:
  18 Persistence, 16 Console and 22 frontend cases. TypeScript, changed-file lint,
  Storybook/assets builds and all four root static gates passed. No full suite.
- Build corrections: the direct HEEx renderer accepts a plain map, so defaults
  use Map.put_new rather than Phoenix change-tracked assign_new. Esbuild exposed
  a case-only basename collision between OAuthReceipt.tsx and oauthReceipt.ts;
  renamed the transport helper to oauthReceiptTransport.ts and rebuilt cleanly.
- Real Chrome checks used a local browser client that opened its own OAuth
  window. Both CIMD and DCR approval/denial returned to that exact window, which
  successfully notified its original client opener; the Vxpipe receipt stayed
  open with a severed opener. Approval completed S256 exchange, initialization,
  tools/list, list_tenants, refresh and session reuse, then returned 401 after
  revoke and 400 on code replay. Both denials preserved state and issuer.
- With window.open blocked, the same DCR browser client completed the original
  callback without any extra tab. An unreachable registered loopback callback
  produced ERR_CONNECTION_REFUSED in the original window while the Vxpipe receipt
  still said Access approved and directed the user to finish in the client.
  That recorded grant appeared in Your connections; no exchange success was
  asserted. Backend failures/replay use the separate recovery screen.
- Actual desktop approval, mobile denial and light/mobile no-permission receipt
  render without overflow. Manage connected clients reaches the real list; Back
  to Vxpipe reaches Console home. The temporary Superadmin browser fixture first
  omitted the gateway's browser_auth option for tenant directory reads; correcting
  that test-only setup verified the full home destination. Product code did not
  require a navigation workaround. Existing member/role isolation remains covered
  by the prior real-database and browser checks.
- Design/source review: preserved exact callback construction, session/CSRF/PKCE
  boundaries, current authority and metadata locks, and one-time request behavior.
  No preview-only flag or simulated completion enters the production flow.
  The receipt only persists visibly when an extra window and original request
  window are available; otherwise callback delivery takes precedence. This
  supported scope is documented in the development guide.

## Final release and completion

- Rebuilt production assets, the OTP release and the local Docker image, then
  restarted `vxpipe.service`. Both it and Caddy are active; `/healthz` returns
  `ok`. Public `admin.js`, `oauth.js` and `oauth.css` hashes match the release.
  Image: `sha256:678ce3cfcee1f995de80e545761d0a890a7e98fb906c9ad2ddd5f33f67313c69`.
  The running container is named `vxpipe`, with the unchanged 1 GiB limit and
  approximately 306 MiB observed usage after restart.
- Public Chrome verifies the shared recovery page for a syntactically valid
  request from an unregistered synthetic client, with a working native recovery
  link and no browser errors. No production account or grant was created.
  Initial inspection commands used the former container name, `/health` instead
  of `/healthz`, malformed synthetic client IDs, and the document title as a
  visible-text selector. Corrected these checks against the actual container,
  routes and component; none required an application change.
- Final formatting and changed-file lint pass. Milestone and index now reflect
  complete implementation, focused tests and real browser/protocol evidence.
  The temporary browser test VM, browser sessions and environment-free Storybook
  source copy were cleaned up. Work remains on `qa`; main is unchanged. No full
  suite was run and no environment file was read.
