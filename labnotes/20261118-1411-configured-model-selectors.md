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
