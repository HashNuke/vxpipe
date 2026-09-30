# Speech provider expansion research

The goal now includes Cartesia STT/TTS and ElevenLabs STT/TTS/STS. No speech
implementation is claimed yet. Design evidence and unresolved contracts are in
[the expansion decision](../docs/speech-provider-expansion.md).

## Current evidence

- Official Cartesia docs now identify Sonic 3.6 and Ink 2. Earlier indexed Sonic
  2 examples are stale; use current model pages, not search snippets. The STT
  automatic-turn endpoint is `/stt/turns/websocket`, not `/stt/turns-websocket`.
- Cartesia API version is 2026-08-14. Current examples pass the voice ID directly
  as a string. Do not reuse the older object-shaped voice encoding unreviewed.
- Ink turn updates are cumulative stable text. Distinguish turn start, eager end,
  resume and definitive end. Pace PCM and trailing silence. Close-and-drain is a
  different operation from abruptly closing the wire.
- ElevenLabs current models include v4/v4 Turbo as well as economical Flash 2.5.
  Its Scribe realtime committed transcript is a segment boundary; the docs describe
  automatic commits after approximately 36 seconds even in manual mode.
- ElevenAgents conversation requires an agent ID; voice changer STS does not
  provide conversational agent semantics. A product question about this distinction
  was sent earlier, with no answer received so far.
- Inspecting Descriptor confirms conversational STT admission requires provider
  semantic/gap endpointing and speech-start evidence. Do not pretend Scribe commits
  automatically satisfy that contract. Specify an actual turn owner first.

## Work sequence and barriers

Cartesia's automatic STT has a clear semantic mapping. Request-based complete-text
Cartesia/ElevenLabs TTS can share the existing owned-request pattern while keeping
vendor wire code in each provider directory. Review a shared lifecycle extraction
before copying Google's session three times.

During this research, full-suite failures required a deterministic TTS completion
ordering repair; its red/green history is in
[separate labnotes](20260930-0554-tts-completion-order.md). Selected existing/direct
LLM live checks already passed in the prior checkpoint. No new billable speech
calls were made during this research and the private credentials file was not read
or modified.

## Gateway design correction

The gateway exploration now separates requested model identity, inference host
and client-facing protocol. Cloudflare's documented Deepgram native proxy and
Workers AI-hosted Deepgram have different authentication/routing roles; Vercel's
compatible API can expose model families through one protocol. A small verified
route contract may be needed, but per-gateway upstream model catalogs are rejected.
Tenant override, BYOK fallback and usage identity need explicit approval before
implementation. Primary references and implications are recorded in the gateway
milestone. No gateway code or further billable gateway request was introduced.

Documentation links resolve locally and the milestone index matches its 38 entries
(27 checked, 11 unchecked). Full local Gateway acceptance passed 520 tests after
phone scenario isolation; the latest root rerun includes the corrected STT fixture.
The provider milestone remains open for speech implementation and final acceptance.
