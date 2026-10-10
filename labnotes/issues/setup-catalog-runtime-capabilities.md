# Setup catalog and runtime capability metadata

Status: resolved 2026-09-21.

The earlier Console catalog described future product offerings as if they were integrated. Its
Google, Rime and Telnyx speech badges did not match `Vxpipe.Providers.Registry`. The setup dialog
therefore implied that saving credentials made unsupported call paths available.

The authenticated platform and tenant binding-directory responses now include
`provider_capabilities` from the fixed registry. Setup validates this field, offers only providers
with an installed credential capability, and intersects STT, TTS and telephony labels with the
declared capabilities. Missing catalog data makes Setup unavailable. The frontend catalog contains
only current provider presentation and sample defaults; it no longer contains Vertex AI or future
speech labels. Google and Zenmux LLM entries are explicit metadata for the separate shared ReqLLM
path. Rime remains available for credential storage/testing and is labeled **Credentials only**;
it does not count toward voice sample readiness. The previous future speech-to-speech Storybook
preview was removed.

This does not change call runtime behavior. A manifest declares support, while configured
credentials and owning-runtime startup still determine whether a particular call is ready.

Verification: the endpoint contract first failed because `provider_capabilities` was absent. The
frontend projection, rendered picker, and credential form tests first failed on unsupported labels
and missing current providers. Focused backend and frontend suites pass after implementation.
The local authenticated Console was inspected at desktop and 390-pixel mobile widths: Google
showed LLM only, Rime showed Credentials only, and the telephony picker offered Telnyx and Twilio.
The older onboarding view also showed Credentials only for a browser-local synthetic Rime binding.
No credential was submitted.
The full umbrella suite passed 1,979 tests with zero failures (42 excluded); the Console frontend
suite passed 189 tests. Root format, warnings-as-errors compile, strict Credo and unused-dependency
checks, frontend type checking and lint also passed.
