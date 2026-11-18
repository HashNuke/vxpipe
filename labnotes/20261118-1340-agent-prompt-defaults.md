# Agent prompt defaults and validation

## Approved scope

- Require at least 100 characters of agent instructions in the editor, with plain-language inline guidance instead of a generic byte-count error.
- Include Hangup when creating an agent, including the initial incoming/outgoing handler. Preserve existing agents and allow tool removal.
- User clarified that Save as draft must reject invalid call specs just as publication does. Failed saves keep browser edits and do not insert a revision.
- User authorizes committing before deployment to vxpipe.service and committing the final release evidence afterward.

## Diagnosis and decisions

- Read-only inspection of recent saved validation errors identified unsupported_agent_protocol on the receptionist's language-model selection. No source, credentials or caller data were logged or modified.
- Shared error projection discarded that compiler code and path. Preserve its location and provide fixed, safe, actionable guidance. Map model failures to the Model field; map Idle failures to Tools.
- Generic empty-path errors matched every field and were attached to Default tool visibility. They now remain in the tab's issue summary.
- The current native structured-reply adapter profile admits only the verified OpenAI model. Earlier Gemini candidates failed full-history/tool acceptance, as documented in the structured-messages checkpoint. This patch does not bypass that guard or claim Gemini support.
- Draft saves previously stored compiler errors alongside a revision. Compilation now must succeed before any source revision/routes are inserted. Stored historical invalid drafts remain readable and unpublishable.
- The 100-character rule is editor authoring guidance/validation; the existing portable schema and historical source parser remain compatible. The existing maximum storage size remains enforced with a separate comprehensible error.

## Verification

- Red: six focused frontend regressions for minimum prompt length/default Hangup, two public error projection regressions, one strict-save regression and one root-error placement regression failed as expected.
- Initial editor suite: 412 tests pass after updating valid fixtures to meet the new minimum. Empty/whitespace/99-character and Unicode boundary cases are covered.
- Calls focused checks: 19 tests pass; persistent voice checks: 23 pass, two excluded. API checks assert rejected updates do not advance latest_revision.
- Chromium inspected prompt errors on desktop/mobile; added agents visibly contain Hangup. Model-error Show opens the participant Models tab.
- Full frontend suite: 1,157 tests pass across 148 files. Final Calls suite: 392 pass; Persistence: 546 pass (68 excluded); Console: 573 pass (122 excluded). Shared schema contract: 81 pass; Gateway write/JSON boundary: 12 pass; Artifacts: 20 pass.
- Stricter saves exposed intentionally incomplete identity/CLI fixtures and legacy sample fixtures. Identity fixtures now include a runnable fixture model, sample fixtures explicitly use their legacy sample protocol, and the outgoing missing-caller-ID regression now expects rejection at save. No production compatibility fallback was added.
- Root umbrella attempt hit an unrelated DeadlineTest 300ms assertion and ended without complete umbrella totals. The isolated same-seed case passes. An existing BillingEnrichmentTest 100ms assertion failed under concurrent load; the final sequential Calls suite passes unchanged. No clean single-process full-umbrella pass is claimed.
- Format, warnings-as-errors compile, strict Credo, unused-dependency check and TypeScript pass. ESLint has no errors and one pre-existing SetupDialog hook warning.
- Final browser confirmation highlights the actual Model dropdown for the unsupported-profile error; generic errors stay in the summary. Production release verified below.

## Production release

- Committed implementation as `8e1d248cf1deb384ce779fa57ff0bb507db0daaa` before building production assets and the assembled release; both builds succeeded.
- Retained the previous image as `vxpipe:before-agent-validation-20261118`. Built image `sha256:c35fc9e9a3a424aa7087f212489c24ce0f7b25a235380f67ae2c710bccb3e533` with the implementation commit in its OCI revision label.
- Restarted `vxpipe.service` through systemd, including its packaged migration preflight. The running container matches the new image and revision; service reports active/running, success and zero restarts. Caddy is active.
- Local and public health endpoints both return `ok`. Public admin JavaScript and CSS SHA-256 hashes match the assembled release; running CallSpecs and CallSpecErrors bytecode hashes also match.
- Existing Gemini profile restrictions remain unchanged. This release fixes validation/defaults and error placement; it does not enable Gemini structured-agent support or modify user call specs.
