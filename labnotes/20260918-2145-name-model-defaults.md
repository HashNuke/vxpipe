# Name model defaults

- Set Deepgram convenience defaults to STT flux-general-multi and TTS flux-hannah-en, exactly as supplied by the user.
- Renamed the catalog field from models to defaultModels for every provider, including both Google providers. Updated sample rendering, previews, readiness lookups, type definitions, test naming and active design documentation to call these defaults rather than recommendations.
- Defaults are convenience selections, not model restrictions. Added no explanatory UI copy, per user instruction. Kept Google defaults and explicit sampleCapabilities unchanged.
- Configuration/mechanical rename: no new literal-value tests or initial red test. TypeScript and all 20 focused onboarding tests pass; git diff --check passes.
- Headless Chrome verified the samples page and recipe preview display flux-general-multi, gemini-3.8-flash and flux-hannah-en. Screenshots: ignored tmp/onboarding-storybook/model-defaults-samples.png and model-defaults-preview.png. Closed only model-defaults browser session; Storybook remains running.
- Preserved existing staging and unrelated work; no commits, backend edits or bin/dev changes. Existing broader verification is recorded in the preceding checkpoints.
