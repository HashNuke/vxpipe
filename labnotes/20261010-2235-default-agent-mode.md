# Exclusive default agent models

- Request: Call settings must choose LLM + Text-to-Speech or Speech-to-Speech,
  with only the selected model path visible.
- Added a Model type selector consistent with the participant inspector; retained
  provider/model rows and the recently adjusted spacing. Human transcription is
  separate. Loading a saved document does not normalize its capabilities.
- Source inheritance is per capability and cannot suppress one inherited model.
  An explicit call-wide change therefore clears incompatible defaults and agent
  overrides, seeds missing recommended selections, and preserves compatible
  overrides and human settings.
  Hiding controls alone would leave agents with conflicting effective models.
- Red: defaults-panel tests failed in four cases because Model type was absent.
  Green: 21 tests passed across defaults-panel and agent-inspector, covering both
  transitions, source preservation, saved STS, read-only and unavailable models.
- Verification: all 547 frontend tests (70 files), TypeScript and ESLint passed.
  Root format, warnings-as-errors compile, strict Credo and unused-dependency
  checks passed. Root `mix test` reproduced the pre-existing Ortex macOS NIF
  `mis-aligned LINKEDIT string pool` failure in packaged acoustic inference and
  activity supervision; stopped that run after confirming the same native-load
  blocker. It did not complete, and no umbrella-wide green result is claimed.
- Rendered Chrome review via agent-browser: dark 1440px and light 390px, both
  model paths, Cartesia voice field, recommended selections when switching back,
  and separate human controls. No horizontal overflow at 390px; Provider, Model
  and Voice labels retain 6px field spacing. Captures are in
  `vxpipe-default-mode-{desktop,mobile}-{llm,sts}.png` plus desktop voice in the
  temporary verification output directory.
- Storybook remains listening on port 6006. Closed the verification browser.
- Later review put Model type and its dropdown on one line in both call defaults
  and agent Models, and removed the call-wide explanatory sentence at the user's
  request. Existing labels and help/error associations are preserved. The latest
  26 focused frontend tests, TypeScript and ESLint pass; desktop and 390px mobile
  rendering verified. The final umbrella run completed with the same 6 Ortex
  engine failures and 1 configured ElevenLabs Console readiness failure; other
  umbrella suites passed. Detailed evidence is in the compact voice-picker labnote.
