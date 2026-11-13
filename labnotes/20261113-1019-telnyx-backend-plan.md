# Shared Telnyx backend planning

Historical planning record. The draft below was simplified to three checkpoints
and 12 tasks, then tightened to nine tasks in the
[subsequent review](20261113-1123-simplify-telnyx-milestone.md). The milestone owns
the current scope and implementation status.

## Scope and source evidence

- User requested planning and a milestone before implementing backend support for
  the reviewed Telnyx modal. This checkpoint changes documents only; earlier modal,
  key-generator and labnote work remains intact and uncommitted.
- Inspected the milestone index, completed scoped-service/Telnyx/outgoing contracts,
  current installation-origin handling, Calls configuration/authorization/admission,
  Persistence services/routes/claims and Gateway signing/retained-owner/URL paths.
- Current application ID lookup and the scoped application unique index assume one
  tenant service per application. Published-number conflicts and durable incoming
  claims are currently tenant-scoped. Both need changes before shared routing.
- `PublicEndpoint`, `WebhookSelection`, `WebhookService` and `IngressRegistration`
  use credential owner as webhook scope. Application-only overrides require these
  identities to become independent while retaining the inherited signing key.
- Production currently has separate credential and application operations and
  different write permissions (`tenant_api_keys.write` / `tenant_services.write`).
  A combined modal must preserve those permissions and save atomically.

## Decisions and unresolved choice

- Created a five-checkpoint milestone and a focused design record. Checkpoints
  cover configuration, dedicated override runtime, shared application admission,
  atomic production integration, and migration/acceptance.
- Preserve named services, old IDs/source revisions/ciphertext, active-call snapshots
  and legacy incoming URLs. Do not silently select an existing application as a
  tenant default or redirect provider webhooks on Save.
- Telnyx documentation confirms application-level incoming webhook configuration
  and authenticated event application/called-number fields. The phone-number voice
  settings reference inspected does not establish per-number webhook routing.
- Asked the user about the credentials-only override edge case. The user requested
  consequences with an example before deciding. Explained two tenants sharing one
  application and why changing its webhook redirects both tenants' incoming events.
- D1 remains open: preserve the tenant-URL preview rule and require a dedicated
  application for incoming readiness, or follow application ownership for the URL
  and allow compatible credentials-only overrides on the shared platform URL.
  Recommended the latter; did not treat that recommendation as approval.
- Documented the further constraint that another Telnyx account's credentials do
  not establish access to the platform application. Optional provider testing and
  live calls remain separate from successful local persistence.

## Local design review

- Reviewed prerequisite order and checked that unfinished demo setup, guardrails,
  packaging and retention are not introduced as dependencies.
- Added cross-tenant duplicate-event/leg identity because the current tenant/service
  claim key could admit a delayed event to a different tenant after number movement.
- Added transaction-time route/configuration revalidation, concurrent publication
  and default-change conflicts, foreign-tenant inventory privacy, archived reference
  decoding, legacy endpoint invariants and section-specific authority checks.
- Review is local source/design work; no independent-agent review or runtime/live
  verification is claimed. Implementation checkboxes remain empty.

## Verification

- Checked source and first-party vendor documentation only; no provider API calls,
  database/schema changes, new backend code or browser behavior changes.
- All new document relative links resolve. The index has 62 sequential entries,
  48 complete and 14 incomplete; corrected its previously stale summary count.
  All 36 implementation tasks in the new milestone are unchecked.
- `git diff --check` passed. Planning added only the milestone, design decision,
  this labnote and index updates; no runtime tests were rerun for these documents.

## Simplification after user review

- User asked to avoid overengineering and review the milestone again. The initial
  five-checkpoint, 36-task plan prescribed infrastructure beyond the modal and
  shared-application requirement; it is superseded by the rewritten milestone.
- Reduced to three checkpoints and 12 tasks: persist defaults/overrides, route
  shared calls, and integrate/verify the production modal.
- Reuse existing credential storage, tenant application bindings, number routes,
  admission transactions and leg lookup. An absent tenant application ID inherits
  one platform default; existing explicit IDs remain intact.
- Removed cross-resource revision tokens, additional binding modes, predesigned
  endpoint families, a persisted legacy mode and an operator adoption workflow.
  Retained one transactional modal save and the existing permission checks.
- Kept signature verification, unique number routing and duplicate-call protection
  because sharing changes those actual boundaries. Tests should drive the smallest
  changes to the existing stores, rather than introduce parallel infrastructure.
- The credentials-only URL choice remains open; the user's simplification request
  was not treated as approval of a different webhook rule. Reduced it to one
  ordinary URL/validation decision rather than an account/readiness subsystem.
- Updated the design note and index to match. This is a local design review only;
  no backend code or earlier implementation work was changed.
- Verification passed: relative links, three checkpoints, 12 unchecked tasks,
  sequential index/counts and `git diff --check`. No runtime tests were needed
  for this document-only revision.
