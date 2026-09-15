# Inline Google translation

## Scope and decision

Extract the additive Agent Runtime translation boundary from the pending inline schema cutover.
Public input names Google and a provider-local model. The module validates bounded common and
Google-specific options, rejects private transport fields and adapter names, and translates to
ReqLLM internally. It pins the Google endpoint and header-authentication mode. No credential is
accepted or returned by this translator; the caller supplies the tenant credential separately.

Provider option mappings belong to Agent Runtime so the call schema does not expose ReqLLM’s
adapter details. Arbitrary options, callback injection and endpoint overrides were rejected.
The initial scope supports Google; other upstream providers remain milestone work.

## Evidence

- The explicit-streaming assertion first failed, seed 531052, because installed model metadata
  omitted streaming text support. Selecting Google’s text streaming protocol fixed the assertion.
  Earlier focused translation checks passed 2 tests, seed 257037.
- Extracted the module and focused tests into a detached checkout of `8dc1cbe`, excluding the
  pending schema/configuration changes. The owning Agent Runtime suite passed **93 tests,
  0 failures, 4 excluded**, seed 140267. Synthetic option markers only; no provider calls were made.
- Root formatting, warnings-as-errors compilation and strict Credo passed.
  Dependency declarations and lockfiles are unchanged. Full umbrella completion checks remain
  scheduled with the consuming inline-schema cutover.
