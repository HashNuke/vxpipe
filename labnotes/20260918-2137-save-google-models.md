# Save Google models

- Saved the exact user-selected STT/LLM/TTS model IDs for both Google AI Studio and Google Vertex AI in setupCatalog.json: gemini-3.5-transcribe-live, gemini-3.8-flash, gemini-3.1-flash-tts-preview.
- Added explicit sampleCapabilities to separate recommended models from current adapter support. Preserved existing setup gating: Google contributes LLM, Vertex contributes no runnable sample capabilities, and the future speech-to-speech fixture explicitly opts into its preview capability. No Google speech or Vertex runtime integration is claimed.
- Configuration update and behavior-preserving separation: no new literal-value tests or initial red test. Existing 20 onboarding tests pass, including both Google cases remaining incomplete without supported speech services. TypeScript and git diff --check pass.
- Rendered the samples story in headless Chrome and confirmed the language-model recommendation now displays gemini-3.8-flash. Screenshot: ignored tmp/onboarding-storybook/google-models-samples.png. Closed the google-models browser session; Storybook remains running.
- Preserved user staging and previous work. No backend changes, commits, or server restarts. The prior full frontend/build and umbrella verification remains documented in preceding checkpoint notes.

- Follow-up: saved gemini-3.8-live as the speech-to-speech recommendation for both Google entries, added the capability label, and made the future speech-to-speech fixture use the catalog recommendation instead of a placeholder. Runtime capability gates remain explicit.
- Follow-up verification: TypeScript and all 20 onboarding tests pass. Chrome showed gemini-3.8-live in the speech-to-speech sample preview and all four Google capability labels wrapping within the mobile card. Screenshots: google-live-model-samples.png and google-four-capabilities-mobile.png under the ignored Storybook artifacts directory. Closed google-live-model browser session.
