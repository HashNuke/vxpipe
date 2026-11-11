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
