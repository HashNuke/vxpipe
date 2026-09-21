# Rime and Google speech

2026-09-21. Started after the unified service-card UI checkpoint `ee299d3c`. The worktree was
clean. All four saved platform records (Deepgram, Rime, Google, Telnyx) were observed by a
read-only query in the earlier checkpoint; Deepgram, Rime and Google credential probes returned
valid without logging keys. A credential probe does not establish speech model availability.

Official Rime documentation describes `/ws3` batch `done` events and `clear`, but `clear` only
removes buffered text. Its streaming HTTP Coda endpoint accepts complete text, streams PCM and
ends one response per utterance; this initially looked simpler.

Two local, one-utterance probes with the saved platform credential changed that decision. The
HTTP endpoint (`audio/L16`, Coda, astra, 24 kHz) returned 200, 72,960 even-byte PCM bytes,
first audio at 1,471 ms and completion at 1,890 ms. The JSON WebSocket with `segment=never`
connected in 1,387 ms, then after complete text + flush returned first audio in 538 ms and a
`done` in 1,601 ms, with 69,120 even-byte PCM bytes. Neither script logged the key or audio;
both stayed in `/tmp`. These are single samples with different utterances and do not establish a
distribution. They do show the value of preparing a socket before a call needs its next TTS
utterance. The design now selects a prepared WebSocket and retires it upon cancellation unless
the protocol can prove output is fenced. An initial probe pattern mismatch printed credential
metadata, including a last-four hint, to the tool output; the script was corrected before either
network request. No secret or hint entered the repository.

Google's current dedicated TTS and live-transcription APIs use different transports. Live
transcription documents interim and final text and provider VAD, but does not document a separate
speech-start event. An isolated synthetic-audio probe is required before declaring conversational
STT because barge-in currently depends on prompt speech-start evidence.

Design decision and vertical acceptance gates are in
`docs/milestones/rime-and-google-speech-providers.md`.

Rime adapter progress: focused protocol, semantic-session and call-plan tests were red before the
adapter/manifest work, then passed. The adapter serializes text and flush with `segment=never`,
uses the shared Mint socket after moving that transport out of the Deepgram namespace, and
holds completion behind audio credit. Cancellation drops the remaining audio through `done`.
The real semantic session using the saved credential reached ready in 1,293 ms, first audio
531 ms after speak, completed generation in 1,147 ms and delivered 72,960 PCM bytes. These are
single-run diagnostics, not a latency distribution. A failed root-build attempt made an Elixir
exception print the saved key to local tool output; the key was not put in the repository and
should be rotated. Subsequent probes print only timings and counts.

The bounded controlled Rime run completed eight isolated sessions with ten credited requests
each under four schedulers: 80/80 successes, p50 0.231 ms, p95 4.116 ms, p99 4.129 ms from
request to settled playback. An early harness run returned busy on a subsequent turn before the
harness settled the previous output; the corrected harness passed serial reruns. This is not a
provider wire failure. The unchanged Deepgram controlled regression completed 32 sessions × 20
requests (640/640) under the same four-scheduler cap. With the Storybook server stopped, its
completion p50/p95/p99 was 0.729/1.713/3.126 ms and settlement was 1.019/1.958/3.563 ms,
below the previously recorded 1.404/3.822/4.622 ms completion and
1.992/4.623/5.582 ms settlement baseline. Runs while Storybook was polling had noisier p99
values; they do not isolate a code regression. All reports were generated outside the repo.

Rendered Storybook checks at desktop and 390 px mobile displayed Rime TTS on tenant setup and
platform service cards. The tenant services inventory also displayed Rime TTS after its synthetic
save action. The service lists stayed within the mobile viewport. The two-row capability-tag
layout was verified in the prior unified-services checkpoint.

API naming correction: Coda and Flux are model families, so the Rime capability entry now names
`Rime.TTSSession`, with `Rime.TTS` owning Coda's current wire/configuration details. The Deepgram
capability names and TTS voice-to-model mapping still need the same cleanup in a separate provider
checkpoint. The Rime rename passed its focused session, plan-startup and telemetry tests.

Rime checkpoint verification: format, compile with warnings as errors, strict Credo and unused
dependency check passed. The frontend check, lint and 196 tests passed. The first default
umbrella run had four CallEngine timing failures, including a one-second Rime test startup wait;
all ten tests in the affected speech files passed together on rerun. A lower-concurrency
CallEngine run had one different 100 ms archive assertion timeout; that file passed in isolation.
A serial umbrella run passed all 854 CallEngine and 118 Calls tests before its longer Gateway
portion was stopped for the next implementation checkpoint. The default suite failures varied
with test scheduling and do not establish an application regression. Final umbrella verification
remains an acceptance gate.
