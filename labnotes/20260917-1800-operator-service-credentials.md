# Operator service credentials

## Scope

Implemented checkpoint 6 of `operator-login-and-admin-dashboard`: an installation operator can
list tenant service metadata and create credentials for the providers Vxpipe already supports.
The workflow is create-only and has no secret-read response.

## Decisions

- `Vxpipe.Calls.OperatorAdministration` owns installation-operator authorization and validates
  tenant containment on repository responses. Console calls this boundary rather than Persistence.
- The service directory combines provider credential metadata with read-only telephony service
  metadata. Adding Telnyx or Twilio credentials does not register or rebind telephony services.
- Persistence selects only credential metadata fields and returns bounded, consistently linked
  credential and telephony metadata with an explicit `truncated` marker when more rows exist.
- Console accepts only the existing Google, Deepgram, Zenmux, Telnyx and Twilio credential shapes.
  It derives `auth_kind` server-side and returns metadata only.
- The React boundary validates exact response keys, IDs, provider/auth-kind combinations, tenant
  identity and telephony credential references before rendering them.
- Credential secrets remain in form/request-local state. They are cleared after cancel, success,
  validation failure, duplicate conflict and storage failure.
- Stale submissions are aborted and ignored when another submission starts or the route changes.
- Closing credential setup also aborts and invalidates its submission, so an old response cannot
  close or overwrite a newly opened draft.
- Phoenix filters the complete `values` request container, including malformed nested or scalar
  shapes rejected before the provider-specific parser accepts them.

## Red-green evidence

- Calls tests first failed because `ServiceDirectory` and the operator workflow did not exist.
- Persistence tests first failed because `AdminStore.list_services/2` did not exist.
- Console endpoint tests first reached the React catch-all because the service routes did not exist.
- Frontend tests first failed because the service parser, route and credential submission path did
  not exist.
- Rendered browser inspection exposed that a duplicate response retained the secret input. A focused
  test reproduced it before the form was changed to clear secrets for every terminal result.
- GPT-6 Astra xhigh review found unbounded/full-row service reads, malformed-value log exposure and a
  dismissal/reopen race. Its follow-up found that rejecting oversized inventories made the page
  unusable, then found that an omitted telephony registration could be mislabeled as absent. Each
  finding received a focused failing test before the fix. Partial inventories now mark an unmatched
  telephony credential's registration state as unknown.

## Verification

- Calls focused suite: 12 tests, 0 failures.
- Persistence focused suites: 16 tests, 0 failures.
- Console service endpoint suite: 4 tests, 0 failures.
- Full Calls suite: 101 tests, 0 failures; Persistence: 151 tests, 0 failures; Console: 180 tests,
  0 failures.
- Console asset suite: 109 tests, 0 failures; TypeScript and ESLint passed.
- `ServiceCredentialForm` after the browser fix: 6 tests, 0 failures.
- Rendered at 1440×900 and 390×844 in Chrome through `agent-browser`. Verified empty and populated
  inventory, Google credential creation, Twilio-specific fields, duplicate conflict, secret clearing,
  workspace navigation, browser-history restoration and no mobile document overflow.
- The partial-inventory Storybook state was rendered at 1440×900 and 390×844. Its notice and unknown
  registration state remain visible, with horizontal overflow confined to the inventory table.
- The temporary browser credential was deleted after verification.
- Umbrella completion gates passed: formatting, warnings-as-errors compilation, strict Credo, all
  tests and unused-dependency check.

## Notes

- An initial browser navigation used `127.0.0.1` after login on `localhost`, so the host-only session
  cookie was correctly unavailable. Repeating the check on the configured `localhost` origin worked.
