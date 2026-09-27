
## 2026-09-27 planning pass

- Extracted every unchecked box in `docs/milestones/agent-speech-to-speech.md`
  (awk over `- [ ]` items) and compared it with commits since 2026-09-23 and
  the GPT-Live completion plan.
- Finding: many open parent boxes are stale. Their children are checked, or
  later commits delivered the work (`b9075c39`, `d785a1cb`, `9427ad0b`,
  `ebeaef8f`, `9700df3a`, `d883ce13`) without ticking them. The plan's
  package 0 reconciles them before any code work.
- Verified in code: `RoomAuthority.SpeechToSpeech.Tools.invocation_for/2`
  returns `:deferred` for anything but blocking host tools and participant
  transfers, so variable, MCP and non-blocking STS tools currently wait
  forever. This is the real gap behind the ~1517 task.
- Verified: `Capability.SpeechToSpeech.Hold` branches on `hold: :mute`; other
  providers fail closed with `:unsafe_hold` on a dirty hold.
- Four scope decisions (Google STS, hosted output-STT, `:stop` hold reuse,
  STS tool conversation semantics) are left for the user, with
  recommendations. Plan: `docs/agent-sts-completion-plan.md`.
- D4 agreed with the user: one native result per STS tool call by default.
  Non-blocking uses the model's native async support where it exists,
  otherwise a context append (GPT-Live commentary/thinking), never user text.
  Each integration is reviewed case by case. Google's Live tools page lists
  async function calling for Gemini 2.5 Flash Live but not 3.1 Flash Live;
  support for the pinned 3.8 model is unverified. The `late_tool_results`
  descriptor fact is `:none` for current adapters in this milestone.
- User refinement: `late_tool_results` is per model, not per adapter module,
  because one provider can offer models with different support. Plan: a model
  profile table in each adapter, keyed by model ID and resolved by the config
  constructor (`GPTLive.new/1` currently accepts only `gpt-live-1`). The
  descriptor and admission read the same profile. Runtime config cannot enable
  a mechanism without adapter wire code.
