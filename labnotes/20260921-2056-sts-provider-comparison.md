# STS provider comparison — 2026-09-21

## Scope and evidence

- Read-only research and milestone refinement. No real provider session,
  billable call, synthetic load, code implementation, database write, or
  commit was performed.
- OpenAI's [Realtime model card](https://developers.openai.com/api/docs/models/gpt-realtime-2.1)
  confirms native conversational audio in/out. Its
  [Realtime guide](https://developers.openai.com/api/docs/guides/realtime-conversations)
  separates output audio, output transcription, response completion and VAD
  events. On a WebSocket, interruption needs a local playback stop and
  `conversation.item.truncate` at the played duration; the API cannot align a
  truncated transcript precisely to audio.
- The separate [GPT-Live session guide](https://developers.openai.com/api/docs/guides/live-conversations)
  says transcript deltas carry approximate times but lack item IDs and a
  completed-turn marker. Its output audio deltas lack timing/done events.
  This needs a different settlement proof from Realtime.
- ElevenLabs' [speech-to-speech endpoint](https://elevenlabs.io/docs/api-reference/speech-to-speech/stream)
  is a voice changer, not a conversational agent model.
  [ElevenAgents](https://elevenlabs.io/docs/eleven-agents/overview) is a hosted
  STT/LLM/TTS stack; its [events](https://elevenlabs.io/docs/eleven-agents/customization/events/client-events)
  document agent text arriving after audio starts and a correction after
  interruption.
- Reference implementation inspection found one approach using response-item
  identity plus recorded playback position to truncate the model context.
  The current implementation handles zero played audio by deleting the item.
  Another approach uses elapsed time capped by generated PCM duration and
  switches between provider turn events and local VAD. These are design
  evidence, not tests of Vxpipe; neither approach substitutes for Vxpipe's
  room policy and sink acknowledgements.
- Google's [Live API reference](https://ai.google.dev/api/live) states output
  transcription settles before `generationComplete` or `interrupted` but is
  unordered relative to audio. Its
  [VAD guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
  says interrupted history retains content already sent to the client. That
  may include audio the room has not yet played.

## Decisions and open gate

- Kept OpenAI outside the first STS implementation slice. Its Realtime API
  looks contract-compatible once admission, turn source, transcript settlement,
  played-duration truncation and policy checks are proven. GPT-Live has a
  different event shape and must be evaluated independently.
- Excluded ElevenLabs voice conversion from conversational STS. A future
  hosted-agent or voice-conversion integration needs its own contract review.
- Expanded the existing milestone gates for explicit turn control,
  room-authorized barge-in, mid-turn policy revocation, transcript permission,
  zero-playback interruption, corrected/late transcript, and model-history
  agreement after interruption. The room remains the authority for public
  turns and transport-egress evidence; the current sink cannot prove remote
  hearing.
- Follow-up review corrected the assumption that human STT must drive STS
  endpointing merely because its transcript is selected. The selected caller
  transcript is human STT when present, otherwise STS input transcription;
  the agent uses STS output transcription or explicit agent-output STT.
  Provider, external, and documented hybrid turn-control modes remain
  candidates. [Google](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
  documents all three activity modes, and
  [OpenAI](https://developers.openai.com/api/docs/guides/realtime-vad) documents
  server and semantic VAD. No quality comparison has been run.
- Independent plan review found that the existing sink's paced acknowledgement
  is local egress evidence, not proof of remote hearing. The milestone now
  labels it accordingly. It also distinguishes the already-submitted tool
  invocation (which survives ordinary speech interruption) from a cancelled
  provider response association, and adds an external/hybrid input-activity
  operation. These are plan corrections, not implemented behavior.
- The Google history difference is an **unproven risk**, not measured Vxpipe
  instability. Its hosted badge stays gated until an isolated fixture and,
  only if separately authorized, a bounded interoperability test establish
  acceptable behavior or a mitigation. No decision to pause an active
  implementation was needed because this task changed the plan only.

## Verification

- Reviewed official vendor documentation and current reference source on
  2026-09-21. No provider credentials were read.
- Local Markdown targets resolve, changed files end with newlines and have no
  trailing whitespace, and milestone implementation boxes remain unchecked.
  `git diff --check` passed. No code tests apply to this documentation edit.
