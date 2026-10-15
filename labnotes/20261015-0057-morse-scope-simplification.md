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
