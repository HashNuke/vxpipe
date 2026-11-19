# Mixed STT diagnostics

## Scope

Configured acceptance for accepted human Scribe STT inputs controlling a Morse STS
agent in external/hybrid modes, with operational local Silero on/off. The native
STS-only case proves no diagnostic allocation despite admitted native input audio.
This checkpoint changes tests only; no STS provider implementation or call control.

## Fixture corrections and evidence

- Initial fixtures stopped at startup: setup audio awaited egress acknowledgement,
  and the Console SpeechConnection fixture prepares only STT ingress. Disable setup
  audio for this fixture and reuse the existing Engine TestTransferConnection,
  which prepares both STT and STS resources. No production fix was needed.
- First post-startup PCM can share the admission cutoff millisecond and is correctly
  rejected stale. Start the synthetic 32 ms frame after one frame period; do not
  weaken admission or invent future receipt timestamps.
- Five configured cases pass. Four prove selected human activity origin, real
  activity-turn start with the same generation/source and completion clearing it,
  persisted provider/room timing on the human run and nullable response stages.
  Exact marker bytes reach Scribe and only the expected reuse/fallback inference
  path. Post-room-DOWN checks reject duplicate marker bytes/inference/commits.
- Native STS admits a silent audio frame through its real ingress and drains it,
  while candidate reconciliation has no STT source, no worker, no diagnostic row
  and no inference or Scribe allocation.

## Review and remaining acceptance

Independent review reproduced a false-positive native audio assertion: holding
STSIngress before push still passed because held input returns :ok and an empty
queue. Retain the public Morse provider quiescence transition (true before input,
false after drain) to prove actual admission, including capability-side discard.
Final configured selection passes 17/17. Independent review passes 5/5; the held
mutation now fails exactly at the provider-consumption assertion. Final scoped
review is clean. Canonical-completion acceptance is complete with the preceding
no-agent evidence; broader routing/replacement eligibility stays open.
Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
No live provider tests, Telnyx changes, full suite or deployment.
