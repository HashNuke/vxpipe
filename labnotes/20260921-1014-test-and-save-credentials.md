# Test and save credentials

## Objective

Separate optional upstream credential testing from encrypted credential persistence. Operators must
be able to save a locally valid provider credential even when Vxpipe has no safe provider probe or
the provider is temporarily unavailable.

## Red evidence

- The Calls-focused test failed because `validate_operator_credential/7` did not exist as a
  read-only operation.
- Console endpoint tests showed that create/replace still invoked the upstream validator, and the
  proposed `/credentials/test` routes returned 404.
- Credential-form tests could not find a **Test credentials** action because the form exposed only
  the coupled submit action.

These failures established each project-owned boundary before implementation.

## Decisions

- **Test credentials** and **Save** are independent actions. A test never persists, and a save never
  makes an upstream request.
- The test endpoint distinguishes rejected credentials (422), an unsupported probe (501), and
  temporary unavailability (503). Every result leaves Save available after the request completes.
- Test results are ephemeral UI state. Editing any credential field clears the result. Tests and
  saves do not write `last_validated_at`; existing timestamps remain historical metadata.
- Calls owns installation authority and local provider/auth validation. Console owns operator HTTP
  endpoints and the production HTTP probe adapter. Persistence remains behind the existing Calls
  create/replace operations.
- Provider-specific request construction now lives in
  `Vxpipe.Console.Provider.<Provider>.CredentialValidation`. The configured validator is a thin
  fixed-registry dispatcher with shared timeout and response classification. This follows existing
  provider namespaces without introducing a new umbrella application or package loader.
- The fixed registry has no generic or legacy fallback. Unknown providers and unsupported auth
  kinds return `provider_validation_unsupported`; Save does not invoke the registry. Stale,
  unreachable save-controller branches for the former coupled validation errors were removed.

## Findings and implementation notes

- Telnyx credential payloads may include an Ed25519 webhook public key. Its API authentication probe
  must ignore that field and use only the API key. An exact one-field clause plus an explicit
  two-field projection prevents the public key from affecting the request.
- Rime uses its authenticated dictionary coverage endpoint with a harmless `hello` lookup, avoiding
  audio synthesis during credential testing.
- Calls already exposed the correct save-only create and replace operations. Console now uses them,
  and the coupled wrapper functions were removed rather than retained as a fallback.
- The worktree already contained the tenant-service visibility refactor and its labnotes. Those
  changes were preserved and the credential work was layered on top.

## Verification evidence

- Calls operator-administration focus: 18 tests, 0 failures.
- Console provider-validator and services-endpoint focus: 15 tests, 0 failures.
- Console frontend: 31 files, 185 tests, 0 failures; TypeScript check and ESLint pass.
- Provider-directory refactor: compile with warnings as errors and provider-validator focus pass.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
- A root suite run before the final unreachable-branch cleanup passed. The post-cleanup root suite
  reported one existing gateway WebRTC timing miss in the five-participant handoff test while all
  other umbrella tests passed. An isolated rerun of that exact test passed (1 test, 0 failures), and
  the final credential endpoint/provider-validator focus passed (15 tests, 0 failures). This gives
  no evidence that the credential change caused the transient gateway failure.
- Storybook inspected in Chromium at 1280×800 and 390×844. The add-credential dialog shows separate
  **Test credentials** and **Save** actions; the successful test result keeps the masked draft and
  both actions fit the scrollable mobile dialog. Browser console reported no errors.
