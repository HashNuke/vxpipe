# Morse scope simplification

The user clarified that the intended service is the existing Morse TTS/STT
input/output hosted behind ElevenLabs-style APIs. They explicitly asked to avoid
overengineering and clarified that MorseCodeApiTTS/MorseCodeApiSTT were example
names. This supersedes the earlier complete speech-platform compatibility target.

Repository inspection confirms the Vxpipe implementation already follows normal
adapter structure: one MorseCodeApi manifest, TTS/STT configuration modules and
TTSSession/STTSession. No namespace rename is needed. Existing model display
labels are not an API contract and can follow ordinary catalog conventions.

The previous Go scope grew to 28 output formats, timestamp routes, two TTS
WebSocket protocols, single-use browser tokens, extensive schema/SDK fixtures
and codec packages in the production image. These are unnecessary for the
requested remote PCM provider. Replaced the milestone and design document with
a smaller contract: PCM HTTP TTS, batch PCM/WAV and realtime STT, static discovery,
arbitrary header keys, configurable origin and Railway preparation.

The new checklist explicitly requires pruning unnecessary code/dependencies,
not merely hiding broad compatibility work behind an unchecked gate. Kept
existing interoperability, ordinary provider integration, local endpoint switching
and practical shutdown/failure acceptance. Removed the unopened permission
probe mode added during this turn; ordinary room policy is already tested by
its owner. Kept the completed service-outage scenario as useful network evidence.

Design review: all remaining work serves the hosted Morse input/output contract.
No new speech state machine, generalized compatibility framework, persistence
or paid service is required. Hosted deployment is user-owned; local package
preparation must finish without waiting for it. Historical evidence is linked,
but old complete checkboxes do not imply the reduced Go build has been verified.

Verification for this specification checkpoint: relative links, code fences,
whitespace and diff inspection. Runtime changes remain in a separate checkpoint.

Implementation follow-up: Go commit 1d815f5 removes the unnecessary protocols,
format conversion, token store, pinned schema inventories and separate Railway
SDK module. The runtime is a static Go binary with coder/websocket as its only
module dependency. The user also explicitly confirmed audio should stream;
the encoder renders into 4096-byte buffers and HTTP flushes each buffer, while
STT consumes continuous WebSocket PCM chunks. No complete audio response is
buffered by the synthesis handler.

The new default-PCM/no-codec test initially failed with codec_unavailable, and
unsupported-extension tests initially showed the old endpoints still active.
After simplification all 35 tests/subtests pass under the race detector; vet
passes. Existing slow-reader, client-disconnect and socket-drain checks remain.
A focused first-flush test stops a nearly five-minute response after less than
one second of PCM, proving early delivery and termination on the flush error.

The 2,895,429-byte scratch image ran read-only with 512 MiB, two CPUs and an
injected port different from the published port. The single Go smoke command
passed readiness/auth/discovery, streamed PCM, batch transcription and realtime
partial/final recognition. Missing origin exits 1; SIGTERM exits 0. The owned
container was removed. Hosted Railway checks remain pending user deployment.
Vxpipe's full regression terminates with 3,841 tests, zero failures and 148
exclusions (seed 899255). Its persisted-origin/TLS/outage lane and both ordinary
configured-room scenarios also pass against the simplified binary. Root static
gates pass. No Console UI code changed during simplification; the previous
759-test frontend pass and rendered service/editor evidence still cover it.

Publication: Vxpipe's morsecode-api branch and the Go repository's main branch
were pushed. Go's HTTPS remote had no noninteractive credential helper; using
the existing working GitHub SSH transport for the same repository succeeded.
No token was read, printed or saved. The final status update closes the scoped
implementation and local deployment-preparation gates; user-owned hosted
verification remains explicitly pending. Temporary servers/container/database
were cleaned up and the isolated live-test reservation was released.
