# Speech conformance guide

## Objective

Complete checkpoint G of `docs/milestones/simpler-speech-integrations.md`: extract a shared
provider conformance harness, exercise request, context, batch and segmented provider shapes, and
publish a runnable provider-authoring guide without depending on a hosted account.

## Decisions

- The harness starts every provider inside an explicit allocation-owned `CapabilityTree` scope and
  observes only public session events, credited audio, closure and provider-specific test hooks.
  Provider initialization hooks are configurable; the harness does not assume one wire protocol.
- The request TTS profile starts blocking work under the allocation-local command supervisor.
  It records protocol submission before emitting `:input_submitted`, retains the task reference and
  request token, kills the exact task on cancellation, and ignores stale completion.
- Streamed and bounded whole responses share one semantic output contract. Whole responses are
  checked for byte bounds and PCM alignment at the actual task-result boundary. Both modes allow
  only one uncredited chunk at a time.
- Provider context, synthesis batch and coalesced batch boundaries remain adapter evidence. They do
  not end an engine request. Cancellation keeps the exact request/context identity through cleanup.
- The segmented STT profile keeps revised partials, committed segments, eager end, resume and actual
  turn end distinct. Channel supplies local envelope order when a provider has no upstream sequence.
- The current conversational room path admits only provider-semantic or provider-gap endpointing
  with real speech-start evidence. Standalone descriptors can still describe broader recognition;
  conversational admission rejects shapes whose turn or barge-in authority is missing.
- The guide uses `TTSProvider.credit/4` to match exact Channel credit without exposing the Channel's
  private message tuple. Its complete example is compiled from test support and executed by the
  contract suite.

## Red tests and review findings

- The first contract suite was red with nine missing harness/profile functions. Implementing the
  smallest support modules made the lifecycle profiles executable.
- The compiled guide case was red before the example provider existed. A later version timed out
  when it called the still-missing public credit helper; adding `TTSProvider.credit/4` made the
  example independent of raw Channel tuples.
- The coalesced-batch case initially failed with a session failure before submission evidence. The
  request profile now emits `:input_submitted` only after its worker reports that submission was
  accepted.
- The no-speech-start admission case initially returned `{:ok, state}`. The conversational
  descriptor validator now rejects missing speech-start evidence and unsupported endpointing.
- Astra review found insufficient native Deepgram lifecycle coverage, a hard-coded initialization
  message in the harness, missing held-credit evidence, a stale-result test that did not retain the
  real task reference, prevalidated whole fixtures, and a race between invalid task completion and
  submission acknowledgement. The tests now use controlled native wires, configurable hooks, exact
  credit observation, the captured task identity, task-boundary validation, and held invalid results
  released only after acknowledgement.
- An initial umbrella run found the queued-cancellation test reusing a scope whose deadline case was
  still being removed, producing `{:error, :busy}`. The two independent lifecycle cases now use
  separate explicit scopes; the broader focused suite passes afterward.

## Implementation outcome

- `SpeechProviderContract` provides reusable descriptor, owned-scope, readiness, event, audio,
  draining and queued-cancellation assertions.
- Independent request TTS and segmented STT profiles exercise contract shapes that differ from the
  native Morse and Deepgram implementations. Native providers also pass shared lifecycle checks.
- `docs/speech-integration-guide.md` explains contract selection, public configuration, private
  credentials, supervision, semantic events, exact output credit, cancellation, error handling,
  closed registration and conformance commands. The Call Engine README and provider comparison link
  to it.

## Verification

- Focused conformance suite: 14 tests, zero failures, seed 0.
- Broader speech/capability/native-TTS lane: 154 tests, zero failures, seed 84117.
- The guide's Elixir block exactly matches the compiled support module.
- Repository search over every changed checkpoint file finds no prohibited comparison-project
  references.
- No hosted account or network interoperability claim is made by this structural checkpoint.
- GPT-6 Astra xhigh cleared the final checkpoint with no material P1/P2 findings after the held
  invalid-response barrier was added.
- All five umbrella gates pass: formatting, warning-free compilation, strict Credo, 1,956 tests
  with zero failures and 42 excluded at seed 674921, and the unused-dependency check.
