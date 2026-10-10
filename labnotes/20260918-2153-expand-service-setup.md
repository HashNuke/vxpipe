# Expand service setup

## Scope and decisions

- Storybook review scope: picker limited to Deepgram, Rime, Google AI Studio and Telnyx following user clarification. Deferred Vertex AI, Zenmux and Twilio via availableInSetup while preserving their defaults and production behavior. Replaced onboarding Zenmux/Twilio stories with Rime/Telnyx and added Telnyx AI-only/connected stories.
- Rime uses one API-key field and TTS capability. Telnyx uses an API key and optional public key; user clarified the latter is required only for telephony. Blank keys permit AI-only setup; supplied keys must decode to 32-byte Ed25519 public keys.
- Telnyx belongs to both groups through independent capability membership. Both cards reference one connection. The telephony card says Public key needed until supplied. Updating credentials from either group preserves the other card and an already-configured public key. Manage keeps the originating group in the dropdown.
- Public-key input is an opt-in to the shared credential form, used by onboarding only. Production endpoints/payloads stay as before. Added Rime to shared types/labels without adding it to the production credential chooser.
- No Rime/Telnyx AI model defaults were invented. Runtime sample capability gates remain separate from provider labels. Credential collection does not imply live Rime/Telnyx AI adapters or phone-number routing.
- Primary provider references and integration boundaries are recorded in labnotes/milestones/tenant-setup-experience.md. Local Telnyx webhook verifier confirms a 32-byte key contract.

## Verification

- Red: new connection/form tests failed for missing Rime, Telnyx AI membership/public-key field and restricted picker (9 failures after final scope clarification). Updated tests for optional public key before implementation.
- Green: 29 focused onboarding/form tests pass. Includes API-key-only Telnyx, malformed public-key rejection, later telephony setup, one connection across both sections, retaining configured public keys on API-only updates, secret clearing and four-service picker.
- TypeScript initially found a missing exhaustive Rime fixture label; added it. TypeScript, lint, full frontend suite (156 tests), Storybook build and diff whitespace checks pass.
- Chrome confirmed four AI picker entries, Rime API-key-only form, Telnyx optional-public-key note, and AI-only status in both sections at 1440px and 390px. Adding a valid public key through the telephony card changed both cards to Connected without duplication. Screenshots under ignored tmp/onboarding-storybook/rime-*, telnyx-*.png. Closed all browser sessions used for this checkpoint.
- Browser barriers: Storybook cached removed/new exports, so restarted only the managed Storybook server; the fresh index contains Rime and the three Telnyx stories, without Zenmux/Twilio entries. A manually copied dummy public key decoded to 35 bytes and correctly failed validation; regenerated a 32-byte fixture and completed the browser transition successfully.
- Required root checks all pass: format, compile with warnings-as-errors, strict Credo, full mix test (1,724 tests, 0 failures, 39 excluded), unused dependency check. Evidence: tmp/onboarding-storybook/expanded-services-umbrella.log. Final TypeScript and diff checks pass. Storybook remains running on port 6006.
- Existing staging preserved. No commits or bin/dev management.
