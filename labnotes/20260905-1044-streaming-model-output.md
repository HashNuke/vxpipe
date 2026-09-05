# Streaming model output

## Goal

Deliver complete model sentences to text and speech output as soon as they are
available, while preserving one logical assistant turn. Providers and models
without streaming support must continue through the same output pipeline as one
terminal segment.

## Plan

1. Add a provider-neutral optional streaming contract and a bounded sentence
   accumulator. Keep `generate/2` as the required fallback.
2. Make model inference emit zero or more sentence segments followed by one
   completion signal. Commit conversation history only after successful terminal
   completion; discard partial output on failure or interruption.
3. Teach room authority to keep a turn open across segments, synthesize each
   segment in order, and complete the turn only after generation and all scheduled
   playout complete.
4. Project all text segments through the RTVI gateway as one speaking turn, with
   per-segment spoken progress and a single turn completion.
5. Enable streaming automatically only when the configured ReqLLM model advertises
   text-streaming support. Otherwise use buffered generation.

## Decisions

- The engine streams sentence-sized semantic segments, not provider tokens. Token
  chunks are too small for useful speech synthesis and expose provider-specific
  behavior.
- Streaming is optional at the provider boundary. Lack of support is ordinary
  capability selection, not a provider error and not a retry from a partially
  emitted stream.
- Output limits apply to the complete accumulated response. Invalid UTF-8, empty
  output, overflow, timeout, or provider failure does not enter conversation
  history.
- Interruption cancels the current provider task, drops its unfinished sentence,
  and relies on the existing turn interruption path to clear queued speech.

## Progress

- Inspected the model capability, ReqLLM model metadata, room/TTS lifecycle, and
  gateway turn projection. The current implementation assumes exactly one text
  output and one speech request per assistant turn, so segmentation must carry an
  output identity through playback rather than treating every sentence as a new
  turn.
- Added the optional provider streaming contract and a bounded sentence
  accumulator. The model capability now applies backpressure to provider chunks,
  emits complete sentences early, flushes the final fragment, and sends a distinct
  terminal signal. Buffered providers emit one segment through that same terminal
  lifecycle.
- ReqLLM streaming selection defaults to model metadata and can be explicitly
  enabled or disabled. Development explicitly enables it for the configured model
  because its current catalog record omits the text-streaming flag even though the
  endpoint supports it.
- Focused evidence: 15 model capability, accumulator, and ReqLLM provider tests
  pass. The red run first failed on the missing accumulator, streaming request,
  completion signal, and configuration behavior as intended.
