# Setup provider catalog

## Decision

The fixed provider registry is the source for installed credential, STT, TTS and
telephony capabilities. The authenticated platform and tenant binding directories
now carry `provider_capabilities`. Console validates that field and intersects it
with presentation metadata before showing providers or capability badges. Missing
catalog data leaves Setup unavailable, rather than showing an unverified picker.
Google and Zenmux LLM labels remain separate metadata for the shared ReqLLM path.

Rime is still offered for credential storage/testing, but the UI labels it
**Credentials only** and does not count it toward voice samples. Google shows LLM
only, Telnyx and Twilio show Telephony, and Deepgram shows STT/TTS. The Google
sample default now matches the existing `gemini-2.5-flash` demo sample. The
future speech-to-speech Storybook preview and Vertex AI picker entry were removed.

## Checkpoints and evidence

- The backend endpoint test first failed because `provider_capabilities` was
  absent. It now asserts the six-provider capability map and passes 12/12.
- The frontend projection and rendered picker tests first failed because Zenmux
  was hidden and future badges were shown. The older credential form test first
  failed because Rime was omitted and Vertex AI was offered. After the changes,
  the Console frontend suite passes; TypeScript and ESLint pass.
- The older onboarding inventory also used a Rime speech label. Its focused
  test failed before the label changed to Credentials only. The local Console
  was built and inspected in Chrome at desktop and 390-pixel mobile widths.
  Google showed only LLM, Rime showed Credentials only, and the telephony picker
  offered Telnyx and Twilio. The older onboarding view was inspected with a
  browser-local, synthetic Rime binding response. No credential was submitted.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency
  checks passed. The full umbrella suite passed 1,979 tests with zero failures
  (42 excluded); the Console frontend suite passed 189 tests.

This change does not alter call runtime or process topology. No load test was
needed to assess a call-path regression; the full umbrella suite covers the
existing call boundaries.
