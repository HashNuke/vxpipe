# Google STS input correlation

- Research begins at main `7c2bfb0f` / runtime `6021bc22`; main has no running
  Mix process. Native handoff verification and finite recognition implementation
  have independent agent owners. No caller-correlation runtime changes yet.
- The current Google STS codec ignores `interimInputTranscription`; the session
  emits all `inputTranscription` as partial against mutable `input_turn`, then
  erases that pointer at output settlement. CallerEvents and room CallerTurns
  retain up to sixteen associations until both activity end and final text.
  Therefore earlier output streaming is not complete caller publication support.
- Primary-source inspection changes the next action: pinned Google ADK commit
  `8164341ec5dc7d21d405e553c51cb0bd41cc7afa` handles Gemini 3.x input differently
  from the older accumulated/optional-finished branch. Its receiver treats input
  transcription as one final; the Live reference separately defines the interim
  field. Direct source inspection confirms ADK does not handle that interim
  field; do not attribute both rules to its receiver. Its model-name
  predicate includes gemini-3.8-live. Do not implement the older input profile
  merely because the shared Python Transcription type has optional `finished`.
- The Live reference still says input transcription has independent ordering.
  Keep raw activity, caller final text, model output and playback independent.
  The existing dedicated Google STT owner has a bounded pending-ended-turn queue;
  it is useful local design precedent, not proof of hosted STS correlation.
- Also recorded pinned-model typed-input and interaction-status audits before
  implementation. Upstream distinguishes new typed input from history content
  and distinguishes model end from an interaction still doing work. Do not copy
  history replay, placeholder requests or generic boundary-based input flushing.
- Added concrete unfinished milestone tasks and extended the existing controller
  decision. Next tests must prove final/end/onset permutations, more than sixteen
  completed caller turns, bounded ambiguity/failure and real-room attribution.
  Full overlap, hosted acceptance and interrupted-history proof remain open.

Primary sources inspected 2026-09-22:

- [Pinned Google ADK receive path](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/models/gemini_llm_connection.py#L435)
- [Pinned ADK model predicate](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/utils/model_name_utils.py)
- [Live server-content reference](https://ai.google.dev/api/live#BidiGenerateContentServerContent)
- [Pinned SDK Transcription type](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/types.py#L2051)
