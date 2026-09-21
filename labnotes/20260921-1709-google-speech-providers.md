# Google speech providers

2026-09-21. Started from the clean worktree after Deepgram checkpoint `8be51b54`. Official
Google documentation now uses the Interactions API `response_format: {type: "audio"}` for
`gemini-3.1-flash-tts-preview`, with streamed `step.delta` audio events and a terminal
`interaction.completed`. A saved platform Google credential succeeded on this model. A short
nonstreaming request returned HTTP 200 in 7,147 ms. Streaming requests returned HTTP 200 with
29 and 28 `audio/l16` deltas, 55,680 and 53,760 even PCM bytes. First audio arrived 2,299 and
2,129 ms after request start; full completion took 5,962 and 5,178 ms. The documented output
format is mono PCM16 at 24 kHz. These are small samples, not a latency distribution. Keys, audio,
transcripts and raw response bodies were not logged or put in the repository; temporary probes
and synthesized source audio are under `/tmp`.

The live-transcription probe used a locally synthesized English utterance converted to 16 kHz
mono PCM16 and 100 ms real-time chunks. The saved platform credential worked with a
`x-goog-api-key` WebSocket upgrade header, so no key had to appear in a URL. The first setup
attempt did not produce `setupComplete` within five seconds; later attempts succeeded. A
successful one-utterance run emitted `voiceActivity` `ACTIVITY_START` 235 ms after speech input
began, five interim updates at first 1,123 ms, and `ACTIVITY_END` plus one final transcript at
3,272 ms. A later two-utterance run emitted two starts, two ends and two final transcripts on
one connection, with first activity at 243 ms and first interim at 1,080 ms. No transcript text or
audio was printed. The separate activity event is stronger evidence than interim text for
barge-in, contrary to the initial plan's concern that only transcripts were available.

The provider still has a documented ten-minute session limit; production STT needs a renewal
strategy that preserves call ownership and avoids stale-turn leakage. A five-second setup
deadline appears too short based on the first probe. Neither observation proves instability
from application changes because no Google speech adapter has been integrated yet.

Implementation checkpoint. Added dedicated Google TTS streaming request/session and live STT
socket/session under provider-level capability APIs. Call-spec selection, tenant/platform credential
resolution, fixed registry, demo configuration and Console setup catalog now include the two
capabilities. No persistence schema or stored credential rows changed. Google TTS emits exact
credit-limited PCM chunks and kills its allocation-local request task on cancellation. STT uses
activity start/end plus final transcription, queues a bounded number of late finals, and prepares
a replacement socket at seven minutes, switching at a completed turn. A continuous turn or failed
replacement reaching 9.5 minutes fails closed before the provider's ten-minute limit.

The initial renewal implementation linked the pending socket directly to its active session. A
focused red test stopped the pending socket and showed `Session.push_audio/2` returning
`{:error, :closed}` while the active socket was healthy. The fix starts both sockets under the
allocation's provider DynamicSupervisor and monitors each. Pending failure now leaves the active
socket usable and schedules retry; active socket failure retires only the allocation. Focused
Google STT and call barge-in tests passed after the change. This was a real implementation
instability found by a failing test, fixed before enabling the capability.

Google STT needs PCM16 mono at 16 kHz. WebRTC already normalizes Opus to the selected speech
format. Added Telnyx Opus 16 kHz decoding and Twilio μ-law 8 kHz conversion for the telephony
speech branch, leaving room audio frames in their original format. Focused Gateway media tests
passed. The embedded call fixture initially supplied Opus and could not pass readiness for Google;
supplying its declared PCM16 track let the call-level test exercise actual TTS playout interruption,
interim text and final turn completion. That exposed fixture/format admission, not a production
regression.

Live semantic TTS probe using the saved credential completed with 27 PCM chunks, 51,840 bytes,
2,360 ms to first audio and 5,216 ms total. Live STT accepted 73/73 synthetic PCM chunks in
each of two consecutive-turn probes, returning two starts and two finals. The renewal probe also
switched to a prepared replacement between the turns. Audio, transcript and keys were not
printed or stored in the repository.

Bounded synthetic load on four BEAM schedulers and 16 sessions per lane completed 320/320 TTS
and 320/320 STT turns. Google TTS p99 completion/settlement was 2.221/2.294 ms; STT p99 audio
admission/turn end was 0.642/1.242 ms. A same-bound Deepgram TTS fixture completed 320/320 with
2.669/3.536 ms p99 completion/settlement. Fixture protocols differ, so this is only local
delivery/turn overhead evidence. Browser inspection in headless Chrome covered desktop platform
services and mobile tenant services/onboarding; Google's three service tags wrapped to two lines.

Final verification checkpoint. An umbrella run initially failed one stale Console capability
expectation after the Google manifest gained STT/TTS. The focused endpoint test passed after
updating the expected list. The frontend suite also found two stale Storybook expectations: Google
was previously LLM-only, and an invalid Deepgram override scenario became ready because Google
now supplied all three capabilities. The onboarding test now expects Google STT/TTS, and that
scenario's platform fixture omits Google so it still isolates the invalid override. Frontend
tests, typecheck and lint passed; rendered Chrome desktop/mobile inspection showed the expected
disabled Continue state and service cards.

A repeat umbrella run had two deadline-test failures while Storybook/browser rendering shared the
host. Those 14 deadline tests passed alone after Storybook stopped, and a clean uncontended
umbrella run passed 2,015 default-lane tests across all child apps, including 877 CallEngine,
480 Gateway and 186 Console tests; explicitly tagged integration lanes remain excluded by
default. Formatting, warnings-as-errors
compilation, strict Credo and unused-lock checks also passed. The first uncontended umbrella run
had likewise passed CallEngine and Gateway; its only failure was the stale Console assertion.
There is no evidence of a call stability regression from the completed changes.

The post-fix bounded benchmark ran on four schedulers with 16 sessions per lane and 20 turns per
session. It completed 320/320 TTS and 320/320 STT turns. P99 completion/settlement for TTS was
2.220/2.274 ms; STT audio admission/turn end was 0.547/0.942 ms. A post-fix live saved-key probe
also passed: setup 1,228 ms, 73/73 chunks admitted, `renewed=true`, two speech starts and two
final turns. No key, audio or transcript text was logged. Read-only dev database inspection
showed one platform credential each for Deepgram, Google, Rime and Telnyx, all version 1.
