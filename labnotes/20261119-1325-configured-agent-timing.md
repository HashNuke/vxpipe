# Configured agent timing

- Added a configured, persisted Console call fixture using synthetic Scribe, selective model responses and synthetic Deepgram TTS. The caller requests an actual transfer tool call from assistant to specialist, then submits a second input and receives text and acknowledged audio.
- Initial failures exposed incomplete test connection support: missing handoff hold/release callbacks, candidate preparation and policy subscription. Added only the exercised fixture callbacks. No production or Telnyx implementation changed.
- The transfer preserves the caller's STT session. Diagnostics is agent-scoped and retires its old run; continued caller audio allows normal source discovery to attach the specialist run. The fixture explicitly waits for this attachment instead of fabricating or reusing authority.
- Model tool completion can enqueue another source-agent request. The bounded request helper settles these silently and selects the specialist by its actual prompt.
- Focused routing check passed before adding final assertions for pre-ack audio absence, tool-only response absence and shutdown drain. Full configured fixture suite and independent Astra review pending.
- Final configured suite passes 6/6. It checks matching response command/correlation, absence of an audio landmark before playback acknowledgement, and no response landmarks on the tool-only source turn after shutdown drain.
- One teardown fixture failure was a malformed synthetic SpeechMetadata message without speech_id; adding the matching synthetic ID completed normal TTS egress. This was not a runtime provider defect.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency checks pass. Full suite remains deferred until milestone implementation completes, per user direction. Independent review pending.

- Independent Astra routing run passes 1/1. Its temporary premature-playback mutation fails at the pre-ack absence assertion, demonstrating that the check catches early audio-start reporting. Final scoped Astra assessment is clean and explicitly supports closing the combined C landmark task.
