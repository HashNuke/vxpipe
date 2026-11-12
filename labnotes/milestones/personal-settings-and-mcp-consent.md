# Personal settings and MCP consent

Status: complete on `qa`, including the same-tab callback-button follow-up. Personal settings, connection management, CIMD/DCR
branding, shared consent and real approval/decline receipts pass focused tests
and actual browser/protocol acceptance. The production release runs on Vitrum.

## Runnable slice and prerequisites

A signed-in user reviews an inbound MCP connection with validated CIMD/DCR
branding, authorizes or declines it without breaking the OAuth callback, and can
later find and revoke their own connections under Settings. Their own sign-in
settings live on a separate page in the same sidebar, independent of permission
to administer other users or platform resources.

Prerequisites, in implementation order:

1. [Console authentication and user management](console-authentication-and-user-management.md)
   supplies authenticated sessions, self-account writes and password validation.
2. [MCP OAuth authorization](mcp-oauth.md) supplies browser-bound consent,
   delegated grants, code/refresh lifecycle and per-user revocation.
3. [Installation URL and MCP client metadata](installation-url-and-client-metadata.md)
   supplies installation identity. The subsequent inbound CIMD implementation is
   recorded in [platform MCP clients](../../docs/en/development/platform-mcp-clients.md).

This concerns inbound clients such as Codex connecting to Vxpipe. Tenant-owned
outbound MCP integrations remain in their separate milestone and sidebar.

Design sources: the user-reviewed `OAuthConsentStory`, `Account` and
`ConnectedClients` stories, plus the [initial preview labnote](../20261111-2141-oauth-consent-storybook.md),
[completion/revocation feedback](../20261111-2325-connected-clients-preview.md), and
[personal settings feedback](../20261111-2350-personal-settings-pages.md).

## Approved product contracts

- The main app sidebar exposes Settings. Remove its separate “My account” link.
- Settings retains only the administrative links allowed by the current user's
  permissions, such as API Keys, Roles, Users, integrations and Installation.
- A separate “For you” section follows those links and contains **Your account**
  (`/account`) and **Your connections** (`/account/connections`). Both are available
  to every signed-in user, including users with no platform grants or tenant
  assignments. If no administrative links are allowed, Settings contains only
  “For you”; its main-app entry leads to `/account`.
- Both personal pages use the Settings sidebar, correct active link and mobile
  drawer. They are peers; connections are not nested visually under account.
- Your account edits only the logged-in user's email/password through existing
  self-account APIs. Reuse the user editor's field/password conventions without
  exposing role, membership, enabled-state or other-user administration. Require
  the existing current-password check and preserve password-change sign-out.
- Your connections lists the user's inbound OAuth grants with client name,
  resource and connection/expiry dates. No tenant integration credentials or
  another user's grants may appear.
- Revoke first opens a named confirmation explaining that the client will lose
  access and must connect again to restore it. Cancel/Escape closes without a
  request; confirm submits once. Show pending, retained-row failure/retry, success
  and empty states. Only successful revocation removes the row. Restore useful
  focus and announce the result.
- Consent uses the validated `client_name` and optional standard `client_uri`
  and `logo_uri` metadata. CIMD and DCR share the presentation contract.
  Missing, invalid or failed images use the existing Plug placeholder. Display
  the website with a globe icon, blue link color and permanent underline.
- Consent states who is signed in, the actual delegated actions and tenant
  ceiling, expiry and where to revoke access. It grants no authority beyond the
  existing backend policy. Keep the exact client/callback details available.
- Approved outcome uses product copy and a clear receipt of the approved client,
  scope and expiry. **Back to my app** is the primary action to the validated client callback;
  **Manage connected clients** is the secondary link to Your connections.
  Declined outcome confirms that no new access was granted and existing
  connections are unchanged. Neither screen contains Storybook instructions,
  simulated callback annotations or protocol implementation explanations.

## Current implementation boundary

The self-account page and separate `/account/connections` page use Settings →
For you in production code. The preview flag and embedded account list are
removed. Shared `ConnectedClients` confirmation uses the real per-user API;
Storybook supplies an in-memory adapter to the same page/components.

Production and Storybook now share the reviewed consent component. Validated
CIMD/DCR branding, actual user/authority and grant lifetime reach the production
page; existing clients need no migration. The native consent form preserves the
authenticated POST. Approval and denial render confirmation in that same tab.
Back to my app follows the exact validated callback on user action, including
without JavaScript. Existing CIMD fetch/cache/security behavior is retained;
the confirmation does not claim token exchange completed.

## Implementation checkpoints

### Personal settings routing and self-account editing

- [x] Red-test Settings availability for signed-in users with zero administrative
  grants, zero tenant assignments and ordinary member/Admin/Superadmin roles.
- [x] Wire authenticated direct-load and client-side `/account/connections`
  routes, with refresh/deep-link coverage and ordinary login/session-expiry
  behavior. No platform permission check may gate either personal page.
- [x] Promote the preview sidebar layout to production and remove the preview
  flag after the routes exist. Remove the main-app account link and retain only
  authorized administrative links. Verify desktop/mobile active destinations.
- [x] Keep `/account` focused on self-account editing; move the embedded client
  list to `/account/connections`. Reuse existing form/password validation and
  preserve email updates, current-password errors, pending/failure behavior and
  password-change session revocation. Do not substitute an admin user-write API.
- [x] Test attempted foreign-user targeting and direct access to forbidden admin
  pages still fail; personal access must not broaden platform authorization.
- [x] Commit this runnable slice with tests, docs and checkpoint evidence.

### Connection management and revocation

- [x] Wire the standalone page to the real session-bound list/revoke API, retaining
  the shared confirmation component and its tested cancellation behavior.
- [x] Verify list isolation and revocation ownership with two real users; confirm
  only the selected grant is revoked and its refresh/access/session operations
  can no longer authorize subsequent requests. Preserve other connections.
- [x] Cover loading, empty, list failure/retry, pending confirm, failed revocation,
  expired session, duplicate submission and navigation/refresh after success.
- [x] Verify keyboard focus, cancellation, announcements and readable desktop,
  narrow mobile and light-theme layouts against actual backend responses.
- [x] Commit the working page and reconcile Storybook with production behavior.

### CIMD/DCR branding and consent

- [x] Red-test standard optional branding through CIMD validation/cache and DCR
  registration, persistence, presentation DTOs and the actual consent renderer.
  Existing unbranded clients and old stored records must remain usable.
- [x] Validate and bound optional values at the trust boundary; render all names
  as text. Retain existing client-ID, redirect-URI, public-client, PKCE, resource,
  metadata-digest, cache and SSRF controls. Branding is not evidence of trust.
- [x] Carry accepted `client_uri` and `logo_uri` into consent. Use the approved
  HTTPS link/image policy (no embedded user credentials), no-referrer rendering,
  bounded image layout and Plug fallback for absent/invalid/broken logos. Resolve
  CSP/image-loading requirements without adding unrestricted backend URL fetching.
- [x] Include presentation metadata in the pending-consent consistency checks so
  stale or replaced metadata cannot silently change what a user approved.
- [x] Replace current consent presentation with the reviewed design, including
  correct grants/tenants/expiry, all-tenant/no-action cases, accessible metadata
  details and the Settings → Your connections link.
- [x] Verify CIMD and DCR with deterministic local HTTP peers; keep network/live
  interoperability cases explicitly tagged and excluded from default tests.
- [x] Commit the branding/consent slice with migration or compatibility evidence.

### OAuth completion and protocol continuity

- [x] Before changing redirects, specify how an actual Vxpipe completion page can
  coexist with the client's registered callback. Record the chosen transport,
  who owns the resulting browser window and how failure is represented. The
  preview alone does not establish this protocol contract.
- [x] Preserve successful code/state delivery, denied `access_denied`/state
  delivery, exact validated callback targeting, one-time completion and S256
  exchange. Do not replace the callback with a success page or claim a token
  exchange succeeded merely because consent was approved.
- [x] If a client-owned callback cannot return to Vxpipe, keep the compatible
  callback behavior and record the supported completion-screen scope before
  declaring the screen integrated. No silent mock completion in production.
- [x] Implement approved/declined product outcomes for the supported flow, with
  Back to my app primary and Manage connected clients secondary. Cover callback
  failure, expired/replayed requests, login resume, cancellation and role drift.
- [x] Promote the reviewed unavailable-request screen for rejected/expired/replayed
  requests, keeping error status, no callback, no approval receipt and a real
  Back to Vxpipe destination. Verify the actual browser and shared Storybook UI.
- [x] Exercise real local-client authorize → callback → code exchange → MCP call
  → refresh → revoke, plus denial, for both CIMD and DCR. Record what the browser
  actually displays and what the client receives.
- [x] Commit the completion slice with the decision and protocol evidence.

## Acceptance and completion

- [x] Relevant Identity/Persistence/Console contracts are green from red tests;
  frontend tests, TypeScript, lint and Storybook/assets builds pass.
- [x] Inspect actual app and Storybook on desktop/mobile with agent-browser;
  verify ordinary members can find both personal pages and cannot see admin links.
- [x] Run root format, warnings-as-errors compilation, strict Credo and
  unused-dependency checks, plus focused tests as explicitly requested by the
  user for this implementation. Do not run a full suite. Investigate project-owned failures
  and record accurate rerun evidence; no live-provider credentials are needed.
- [x] Review the final implementation for ownership, permission boundaries and
  OAuth callback continuity; synchronize handbook, stories and checkpoint notes.
- [x] Check this milestone and its index only after production acceptance passes.

## Specification review — separate from implementation

2026-11-11: reviewed dependency order and current source boundaries while drafting.
Routing precedes sidebar promotion; self-account writes retain the Identity
boundary; branding crosses Persistence/Identity/Console rather than staying in a
fixture; callback delivery is an explicit design gate before outcome integration.
Permission-free personal navigation and foreign-grant isolation are separate
contracts. The shared confirmation implementation does not imply that the new
production route, branding pipeline or completion flow is finished.

2026-11-12: independent finish and documentation reviews found the dependency
order, permission boundaries and callback-continuity gate coherent. Corrected
metadata wording to retain the existing required client name while treating the
website and logo as optional. These are specification reviews, not production
acceptance.

2026-11-11 implementation checkpoint: production personal routes/sidebar and the
session-bound connection page verified with focused frontend, endpoint and
real-database tests. A rollback-only browser session exercised a member without
grants/assignments, a separate Superadmin, revocation/reload/isolation, mobile
navigation, wrong-password retry, email persistence and password-change sign-out.
Storybook light/failure states and the app assets build passed; root static checks
passed. See [checkpoint evidence](../20261111-1902-personal-settings-consent.md).
The milestone stays unchecked until the remaining consent/protocol gates pass.

2026-11-11 branding/consent checkpoint: Identity (10), Persistence (18), Console
(13) and shared UI/Storybook (10) focused cases pass, along with TypeScript,
changed-file ESLint, assets/Storybook builds and root static gates. The actual
rollback-only HTTP/browser flow passes CIMD and DCR approval/denial, exchange,
MCP invocation, refresh, revoke and replay rejection. Desktop, mobile, light,
all-tenant and no-permission presentation checked. The client receives and displays
its callback page; Vxpipe outcome receipts are not yet integrated. See the same
checkpoint labnote for the pending browser-experience choice.

2026-11-11 recovery checkpoint: shared unavailable-request rendering replaces
plain-text controller failures. Fourteen Console and eleven frontend cases pass,
including invalid callback rejection and native recovery navigation. An actual
consumed-request reload and desktop/mobile/Storybook checks passed. This records
one completed failure-state requirement; approval/decline receipts and their
callback/window decision remain unfinished.

2026-11-11 completion design review: selected the native form's named-window
transport as the default after the optional UX question remained unanswered.
The original callback window and its client opener are preserved; the receipt
severs its own opener and uses the exact validated callback. Blocked windows keep
the existing redirect. No receipt database or cross-window message protocol is
needed. Presentation and expiry come from the same locked completion transaction.
This review specifies the supported receipt scope separately from the evidence
and does not claim explicit user confirmation of the default.

2026-11-11 completion implementation: 18 Persistence, 16 Console and 22 frontend
cases pass, including stored expiry, denial, duplicate submission, invalid receipt
selection and blocked/detached/unrelated window handling. The real local browser
client verifies original-window/opener continuity for CIMD and DCR approval and
denial, exchange, MCP invocation, refresh, revoke and code replay. Popup blocking
retains the direct callback. An unreachable callback leaves an approval receipt
without claiming exchange succeeded. Actual outcome links, desktop/mobile and
light/no-permission presentation pass.

2026-11-11 completion release: built production assets and the OTP release in QA,
rebuilt the local image and restarted Vxpipe. Health and both system services pass;
public admin/OAuth assets match the verified release. The container retains its
1 GiB limit. This closes the checklist with the browser evidence above; no full
suite was run and main remains unchanged.


## Callback-button follow-up — 2026-11-12

Design review: the user explicitly replaces the separate-tab flow with a
same-tab confirmation and Back to my app action. Both approval and denial use
the validated callback, preserving code/error, state and issuer. Remove the
popup transport and presentation flag entirely. Keep the unavailable-request
recovery link because a rejected request has no validated callback to follow.
The earlier separate-window evidence above records the superseded implementation.

- [x] Render both confirmations in the current tab and wait for the explicit
  callback action, including the JavaScript-free page.
- [x] Replace the outcome's Console-home action with Back to my app; synchronize
  Storybook and remove the popup transport/flag without a compatibility branch.
- [x] Verify exact callback data, CSRF, failure behavior and duplicate submission
  with focused tests; inspect desktop/mobile and real CIMD/DCR callback flows,
  including an unreachable loopback callback suitable for manual URL copying.
- [x] Update documentation, build/release QA, verify deployment, commit and push.

Acceptance: 16 frontend and 15 Console cases pass, along with TypeScript, lint,
root static checks and assets/Storybook builds. Real browser checks cover both
CIMD/DCR decisions, same-tab explicit callback delivery, code exchange/MCP use,
refresh/revoke/replay and the unreachable callback address used by manual CLI
login. Desktop/mobile/light layouts were inspected. The QA release is live on
Vitrum; health/services pass and public assets match the built release.
