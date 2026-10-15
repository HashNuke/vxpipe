# Morse STT provider integration

Continues G after the scoped session foundation in `92292471`. The initial
selection test failed on the missing STT manifest capability. Added registry,
capability/model catalog, private startup resolution, conversational runtime,
usage identity, failure telemetry and development settings. Public options
remain closed; HTTP/WS origins and compatibility keys stay private. The common
conversational wrapper defaults to transcript onset, with no implicit Silero.

The focused selection/catalog/telemetry lane passes 24 tests. Expanded the
persisted-service test from TTS to both capabilities: encrypted platform keys,
tenant override/removal, the same published plan, private HTTP→WS and HTTPS→WSS
origin changes and missing-origin failure all pass. An initial test incorrectly
looked for a single startup STT field; corrected it to the caller's entry in
`speech_to_text_runtimes`. The Console service/runtime/API lane passes 20 tests.

The real Go room test now selects remote STT for both its existing TTS
interruption case and a new input/output round trip. Independently generated
Elixir Morse PCM enters through `CallEngine.push_audio` in paced 20-ms frames.
Two identical E E phrases produce different room turn IDs, nonfinal/final
transcripts, fixture replies and Go HTTP synthesis that the independent decoder
reads as TEST. Playback acknowledgement gates turn completion. Both tagged
tests pass against unchanged Go revision `b922e71` on loopback port 18796.
This is embedded PCM evidence, not WebRTC or browser microphone acceptance.

The normal live runner is reserved by branch main. Its first invocation correctly
refused this branch; that reservation was not altered. Used the runner's explicit
state-directory override for this isolated localhost-only service. `/dev/null`
was rejected because the credential input must be a regular file; a temporary
comment-only file supplied the required input without loading any real keys.
The tests themselves provision synthetic compatibility keys. The protected live
provider file was never accessed. No carrier resources were used.

Two new frontend assertions first failed on the absent STT capability/model and
Morse recognition description. Added the STT catalog fixture, setup capability
and service description; 33 focused tests and all 759 frontend tests now pass.
Headless Chrome renders the service form at 1280×900 and 390×844, including both
speech badges and the Morse-only explanation. The human inspector selects
morse_code_api and displays MorseCodeApiSTT at both widths.

Root formatting, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. The previous foundation umbrella process finished with all apps
passing except the service test edited while that VM still had the old manifest
loaded; its one unsupported-STT failure is invalid mixed-snapshot evidence, not a
passing regression. The new focused Console lane passes with current code. A
fresh full umbrella run is active with runtime/tests left unchanged during it.

Design review: this registers the existing scoped provider through the ordinary
startup and conversation boundaries. No new call state machine, storage or
network fallback is introduced. The two initial G tasks are now implemented and
verified; actual VM restart between origins, local TLS, room permission/outage
and replacement cases, rendered transcripts/errors and final acceptance remain.
No claim of complete G or unrestricted ElevenLabs compatibility is made.
