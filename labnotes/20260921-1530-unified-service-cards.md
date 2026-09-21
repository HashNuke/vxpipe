# Unified service cards

2026-09-21. Replaced the AI/Telephony presentation split in onboarding and
platform services with one installed-provider picker and one connected-service
grid. The production tenant inventory already used one credential list; it now
uses the same connect wording and shows capability tags. Cards and inventory
allow tags to wrap. Removed the “Credentials only” badge, which described missing
runtime work rather than an operator capability.

The persistence review found one `provider_credentials` binding per provider,
name and scope. Telephony application records reference that credential. No
schema change, migration, credential rewrite or database reset is part of this
checkpoint. Existing Deepgram and Telnyx bindings should therefore survive.

The Console had no existing toast component. A small page-level notification
now reports successful service saves/removals and save/removal errors; actionable
form errors also stay beside the form. Tenant inventory save success/failure uses
the same notification. The first tests failed on the grouped sections, duplicate connect
buttons, missing toast and missing tenant capability tags. The focused seven-file
focused seven-file frontend suite passed 80 tests. The final full frontend
suite passed 196 tests across 33 files; TypeScript and ESLint checks pass. Rendered Chrome
inspection used the Storybook onboarding and tenant inventory at 1280×800 and
390×844. The shared cards and one connect action were visible at both widths.
An isolated browser DOM probe added illustrative LLM and Telephony tags to a
mobile Deepgram card: the first three tags began at y=457 and the fourth at
y=488, proving a second row without clipping. The tenant inventory initially
clipped credential previews at mobile width; reflowing each row into a compact
stack made previews, dates, tags and edit actions visible with no page overflow.
The mobile save-success story displayed the notification at the bottom right.
The root format, warnings-as-errors compile, strict Credo, full umbrella test
and unused-dependency checks pass. The umbrella suite has 1,981 tests, zero
failures and 42 excluded. The read-only `vxpipe_dev` metadata check found one
platform binding each for Deepgram, Google, Rime and Telnyx before the commit.
An isolated live validator command resolved the encrypted Deepgram, Rime and
Google bindings from the configured platform store and returned `valid` for all
three; it printed no key, response body or credential metadata.

Provider capability badges still reflect integrated runtime support. Deepgram
has STT/TTS, Google AI Studio has shared ReqLLM model inference, and Rime has
credential validation only. The user has requested real Rime TTS and Google
STT/TTS sessions; those are separate runtime checkpoints and must earn badges
only after speech-contract and live-boundary verification. Real saved keys may
be used for a separate local pass/fail check, never in tests or logs.
