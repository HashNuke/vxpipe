# Provider contract synchronization

## Request and evidence

The user explicitly requested keeping the provider contract document current.
Read `docs/speech-provider-contract.md` completely and inspected the implemented
`Speech.STTProvider`, `TTSProvider` and `STSProvider` behaviours, the STS author
guide, output admission decision and completed baseline migration milestone.

The contract still described a two-of-nine migration prototype, mono-only
WebRTC input, and no STS lifecycle section beyond links. The baseline migration
is nine-of-nine accepted and stereo normalization is recorded as resolved.
STS itself remains incomplete: recent local evidence cannot establish hosted
Google compatibility or close room lifecycle acceptance.

Added a concrete F task breakdown before editing the contract. This is a
documentation synchronization checkpoint, not new runtime behavior. Preserve
the historical research separately from the current normative contract; record
provider-specific buffering/resumption limits without generalizing them to all
providers or claiming pending room/tool publication work is implemented.

The Google output checkpoint `3b1fa264` remains under its live post-commit
umbrella run; do not restart that test session on observation timeouts.

## Contract changes and design review

Replaced the stale proposed/two-of-nine status with the accepted nine-checkpoint
STT/TTS baseline, while leaving the separate STS milestone explicitly incomplete.
Kept the original research and rejected global-startup evidence labeled as
historical rather than deleting it. Corrected the callback inventory (four STT,
five TTS, eight STS), distinguished callback `start_link/1` from helper
`start_link/2`, and replaced the obsolete mono-only WebRTC restriction with the
accepted connection-local stereo-to-mono normalization contract.

Added a normative STS section covering session ownership, directional PCM,
pinned transcript sources versus independent response control, public/private
identity, authorized output credit and actual playback settlement. Documented
bounded pre-admission and active buffering, lossless PCM tails and Google's
specific 16-chunk limit. Included private handle-only resumption, bounded setup,
playback gating, explicit failure and no history/audio/tool replay or fresh
session fallback.

Dependency/contract review: this synchronizes already approved contracts and
recent fixes; it does not introduce runtime work or change acceptance order.
Public caller/tool identity and retirement, native conversations and full room
lifecycle still need implementation/verification. Explicitly separated those
requirements from the proven agent-output identity and embedded transcript-mode
paths. Kept Google history reconciliation false and production selection/badge
gated; local protocol evidence cannot establish hosted interoperability. No new
architecture decision document or runtime regression test is needed for this
documentation-only checkpoint.

## Verification and outcome

- Checked callbacks against `Speech.STTProvider`, `Speech.TTSProvider` and
  `Speech.STSProvider`; output permission/settlement against `Speech.STSOutput`
  and `docs/sts-output-admission.md`.
- Checked queue/PCM guarantees against `Google.STSOutput`, `Google.STS` and
  their buffer, codec and fake-socket session regressions. Checked handoff and
  deadlines against `Google.STSResumption` and `docs/sts-context-restoration.md`.
- Checked baseline/stereo status against the accepted migration milestone and
  resolved WebRTC stereo issue; checked remaining room work against the STS
  milestone and its identity/transcript labnotes.
- Read-only local-link validation: **39 local Markdown targets/anchors pass**
  across the contract, milestone and the two updated labnotes.
- `git diff --check` passes. Reviewed the complete documentation diff before
  exact-path staging; no runtime, timeout, manifest or credential changes.
- The existing post-commit Google umbrella run finished successfully while this
  documentation work was in progress: all five gates pass, **2,205 tests,
  zero failures, 42 excluded**, seed 0. Recorded the evidence in its original
  labnotes and milestone without treating a green retry as a handoff repair.

The contract synchronization tasks are complete. The STS milestone and its
index entry remain incomplete; no hosted call or deployment was performed.
