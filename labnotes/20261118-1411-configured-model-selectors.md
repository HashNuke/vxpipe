# Configured model selectors

- User requests integration display names throughout language, text-to-speech and speech-to-text provider fields, configured choices only, and platform/tenant permission-aware availability with existing saved values preserved.
- ProviderCatalog already filters credential availability by platform-authoring permission, and editor-api loads models only for available providers. Existing authorization and lookup tests cover tenant-only and privileged platform+tenant access (15 pass).
- CapabilityFields discarded display names and fell back to raw IDs except MorseCode. Reuse setupProviders, the same app-owned metadata consumed by the integrations directory's NativeCatalog. Keep the credential-free MorseCode Local label.
- Saved values outside the authorized catalog retain a friendly '(saved)' label only in their existing field. They do not expand the selectable catalog of other fields. Source provider/model/credential references remain unchanged. Unknown saved IDs use an own-property-safe fallback.
- Four regressions first failed on raw labels and the unreadable saved Google selection. Updated existing UI assertions to the intended integration names.
- Google AI Studio runtime support remains separately blocked by the existing DialogueProfile OpenAI allowlist; this patch does not bypass runtime acceptance or claim Gemini support.
- Browser inspection confirms Google AI Studio in the language-model field and capitalized integration choices in the speech dropdown. The narrow tablet inspection was inconclusive because the existing sidebar did not appear in the capture; desktop rendered names were verified. Release evidence follows separately.

## Verification

- All 1,162 frontend tests pass across 148 files, including four added regressions for integration labels and saved inaccessible references. TypeScript passes. Format, warnings-as-errors compile, strict Credo and unused-dependency checks pass.
- Root umbrella attempt hit two unrelated AgentRuntime timeout assertions (DialogueSessionTest:98 and ContextPreparationTest:134). Stopped the broad run after failures; both isolated cases pass with max_cases=1. No clean full umbrella pass is claimed.

## Production release

- Committed implementation as `50663a4b128f31e9dbef1cc3c1c18f6946a8a7a3` before production assets/release builds. Both succeeded. ESLint has no errors and the existing SetupDialog hook warning.
- Retained previous image as `vxpipe:before-integration-labels-20261118`. Deployed image `sha256:51d2ac0fdaf9e7c09d9291bb1aa58cf7258395b280ab9c7a474744d42b8e1aaf` through the systemd migration/restart workflow.
- Container OCI revision matches the implementation commit. Service is active/running, Result=success, NRestarts=0. Local and public health endpoints return `ok`; served admin JavaScript and CSS hashes match the assembled release.
- Google AI Studio agent-protocol enablement remains separate and unimplemented; no user call specs were changed.
