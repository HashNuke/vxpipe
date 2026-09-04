# LLM integration

## Goal

Replace the development room's deterministic text response with a real,
provider-backed conversational turn while preserving the existing
protocol-neutral room, event, RTVI projection, and text-to-speech boundaries.
The first configured provider is Gemini through ReqLLM, using the explicit
model identifier `gemini-3.5-flash-lite`.

## Vertical-slice plan

1. Define a provider-neutral model-inference contract and message type owned by
   the call engine.
2. Add a supervised model-inference capability per room incarnation. It will
   serialize generation, retain a bounded number of completed turns, bound its
   pending queue, and enforce a request timeout without blocking the room
   authority mailbox.
3. Add a ReqLLM adapter that translates engine messages to ReqLLM context and
   passes the configured Gemini credential explicitly.
4. Allow the existing `CreateRoom` path to select a `:model_inference` agent,
   then route its response through the existing `TextOutput`, optional TTS, and
   `AgentTurnCompleted` path.
5. Represent asynchronous generation failure as a protocol-neutral engine
   event. The RTVI gateway will project it as a correlated error response while
   leaving the room and capability available for a later turn.
6. Enable the model-inference agent in development, inject the credential only
   from `config/runtime.exs`, and keep the reusable/default application config
   disabled and credential-free.
7. Verify the capability with a controllable fake provider, verify the full
   room turn, run the umbrella completion checks, and document the durable
   decision under `docs/`.

## System-prompt configuration

The system prompt is agent behavior, not a provider credential and not RTVI
input. For this slice it belongs in the call engine's `:model_inference`
application settings alongside the selected adapter, model-independent runtime
limits, and provider options. The room capability copies that prompt when its
room incarnation starts and prepends it to every provider request. Clients
cannot replace it through `send-text`.

Development will configure a concise voice-assistant prompt in
`config/dev.exs`. A future JSON deployment configuration should map to the same
application setting before the supervision tree starts. A future tenant or
agent-profile resolver can supply different trusted prompts per room without
changing the provider contract; that resolver is deliberately outside this
slice.

Credentials remain separate. `config/runtime.exs` reads `GEMINI_API_KEY` only
when model inference is enabled and injects it into the adapter's provider
options. No credential is compiled into application modules, accepted from the
browser, included in room events, or written to logs and documentation.

## Initial findings

- The call engine currently owns deterministic response generation in a
  temporary capability below each room incarnation's dynamic capability
  supervisor.
- The room authority already serializes participant and agent events and routes
  generated text into optional TTS. Model inference can reuse that output path.
- Audio and typed turns both converge on the protocol-neutral `SendText`
  command, so one capability replacement covers both inputs.
- ReqLLM 1.22.0 is the current Hex release. Its public API accepts provider/model
  specifications and normalizes provider-specific request and response shapes.
- ReqLLM conventionally discovers Google's credential under its own environment
  variable name. Vxpipe will instead pass the configured runtime credential
  explicitly so deployment configuration remains owned by Vxpipe.

## Red-phase evidence

- Added focused capability and room-turn tests before implementation. The first
  run failed during test compilation because
  `Vxpipe.CallEngine.Provider.ModelInference.Message` did not yet exist. This was
  the expected missing-contract failure.
- Added the ReqLLM adapter tests before its module. Their first run produced two
  expected `UndefinedFunctionError` failures for the missing adapter `new/1`.
- A security-contract assertion then demonstrated that the initial provider
  config's default `Inspect` output contained the placeholder credential. The
  focused test failed for that exact reason before redacted inspection was
  added.
- A provider-boundary test demonstrated that an invalid UTF-8 binary was
  initially accepted as generated text. The capability now validates UTF-8
  before trimming or emitting output, reports `invalid_response`, and remains
  available for the next turn.
- The capability tests describe serialized provider work, prompt placement,
  complete-turn history, FIFO limits, failure recovery, and timeouts. The room
  test describes the externally observable command/event path.

## Implementation notes

- Added `ReqLLM` 1.22 to `vxpipe_call_engine`, the umbrella child that owns model
  inference. Version 1.22.0 resolved with an LLMDB snapshot that contains the
  requested `gemini-3.5-flash-lite` identifier under the Google provider.
- Added an engine-owned `ModelInference` provider behaviour and neutral message
  struct. ReqLLM types exist only inside the concrete adapter.
- Added a temporary model-inference GenServer per configured room. It runs one
  provider Task at a time through the named application Task supervisor, queues
  at most four additional development requests, and keeps eight successful
  complete turns in development.
- The provider Task is monitored and has a 30-second capability deadline. The
  ReqLLM transport and total deadlines are 25 seconds, so ordinary request
  cleanup occurs below the capability's outer deadline.
- Provider errors, task exits, invalid or oversized text, and timeouts are
  normalized. The failed turn is not added to history, a sequenced
  `AgentTurnFailed` is emitted, and the next queued turn starts. The room remains
  alive.
- A full capability queue returns retryable `agent_busy` before typed participant
  turn events are emitted. Committed audio turns have already emitted their
  participant events; if their agent enqueue fails, they receive an asynchronous
  `AgentTurnFailed` event instead.
- Generalized the room's text-capability reference to retain both module and PID.
  This preserves the deterministic adapter for tests or alternate room presets
  without adding a model-specific branch to normal text dispatch.
- Development room creation now selects `:model_inference`. Typed input and
  Deepgram-final audio transcripts therefore use Gemini; output continues
  through the existing text event and optional Flux TTS path.
- Runtime configuration injects the Gemini credential into the adapter only
  when development model inference is enabled. The base config remains disabled.
- The ReqLLM provider config derives a restricted `Inspect` representation that
  excludes its credential, preventing ordinary OTP state inspection and crash
  reports from rendering it.
- ReqLLM dependency compilation emitted deprecation warnings from its transitive
  `toml` dependency concerning charlist syntax. The project compilation still
  passed `--warnings-as-errors`; no project-owned warnings were emitted.

## Verification evidence

- Focused model-inference capability, adapter, room-turn, and RTVI codec suites
  passed after their expected red phases.
- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix test`: passed with 41 call-engine tests and 32 gateway tests; four tagged
  integration tests remained excluded by the repository's default test policy.
- One preceding full-suite run missed an existing speech-to-text capability
  `:DOWN` assertion inside ExUnit's 100 ms default window after receiving the
  expected transport-close message. Its focused three-test file passed
  immediately afterward, and the complete 72-test default suite then passed on
  rerun without any code change to that area.
- `mix deps.unlock --check-unused`: passed.
- No live Gemini request was made. This respects the credential boundary and
  keeps deterministic tests independent of provider availability, latency, and
  billing. Manual development-stack validation remains the appropriate live
  interoperability check.
