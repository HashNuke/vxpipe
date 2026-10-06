# Native STS opening

Research began while D6's full local umbrella check was running. At that point no runtime
changes or provider calls had been made. Later implementation evidence is recorded below.

## Current evidence

- `RoomAuthority.FirstMessage.start/1` rejects `generated` for STS with
  `first_message_unavailable`; `fixed` uses the ordinary STS text-input operation.
- The Google STS session's text path submits text then calls `STSInput.open_text_turn/1`,
  which emits caller `turn_ended` evidence carrying that text. Morse STS text input likewise
  emits input transcripts and normally replies with a RECEIVED prefix. Neither path is a
  correct engine-owned opener or proof of exact fixed-text playback.
- The compiler prohibits mixing STS with model-inference or TTS on the same participant.
  Do not silently introduce an LLM/TTS dependency or fabricate caller input to make the
  outgoing STS default pass.
- Existing response-context admission ties output to policy intervals, allocation, source,
  epoch and lifecycle revision. An opener must use those same output authorization fences.
- Google's current official Live API capabilities documentation supports realtime text and
  client-content turns with explicit user/model roles; turn-complete client content interrupts
  generation. Its example triggers audio output from a text cue. That wire role does not
  justify publishing the cue as caller speech in Vxpipe.
  Source: https://ai.google.dev/gemini-api/docs/live-api/capabilities (checked 2026-10-05).

## Next decisions and verification

Start with a focused outgoing STS room test that observes no opening while ringing,
one opener after accepted callee media, actual output audio/agent transcript, and no
caller transcript or accepted-input event from the cue. Establish red before implementation.
Define an explicit engine-owned opening operation at the STS capability/session/provider
boundary, retaining bounded input-slot admission and response correlation. Do not use an
ordinary fake caller text turn as the implementation.

Resolve fixed-text playback separately: model generation alone cannot establish exact
fixed output, and the current Morse prefix makes the existing shortcut observably wrong.
Keep the originally approved mode contract intact; do not call generated-only support full
D3 completion. Cover quiet `wait_for_input`, once-only replay, policy/hold rejection, provider
failure, stale response context and lifecycle cancellation as applicable. Speech/state-machine
changes require the Lean build/oracle/replay gate. No D3 checklist item has been checked.

D6's umbrella run subsequently passed 3,121 tests with zero failures, seed 219668.
D6 is accepted; native opening remains the next implementation task before carrier acceptance.

## Native opening implementation checkpoint

The room tests first failed for the intended observations: generated STS emitted no
opening audio, and fixed decoded RECEIVED GOOD DAY (26 tests, two failures). The session
boundary test failed with missing begin_opening/2 (seven tests, one failure). Implemented
an engine-owned operation through the existing input slot, with correlated submission
and private opening-start evidence. Morse generated/fixed room and session tests passed
33 tests, seed 380984. No caller input is fabricated by the opening.

Google legacy and response-start tests both failed as unsupported (40 tests, two
failures, seed 297980); generated support then passed all 40. Fixed tests failed as
unsupported (44 tests, four failures, seed 994811). Added a private bounded assembly
that releases only when the complete provider transcript exactly matches. The first
fixed green attempt reached output successfully but the fixture incorrectly claimed
20 ms playback for one sample; corrected settlement to the actual bounded duration.
77 focused tests then passed, seed 20715.

Two new replacement tests failed because another opening was accepted before the first
settled (48 tests, two failures, seed 655550); quiescence now rejects that replacement.
Interruption, genuine caller start, missing/different text and overflow release no PCM.
A 100-fragment fixed test exposed the sixteen-chunk limit before implementation; changed
assembly to at most 4,096 fragments/2 MiB and coalesced validated PCM into existing
128 KiB chunks (at most sixteen). Payload order is asserted at the public audio boundary.

Strict Credo identified module-size failures in the capability and Google adapter.
Extracted the cohesive capability opening admission and Google ordered commands; moved
usage-context normalization into its existing Usage owner. Focused verification after
refactoring/assembly passed 84 tests, zero failures, seed 34032. A broader 406-test speech
run failed one 100 ms Morse readiness fixture while 405 tests passed; changed only that
startup wait to an explicit one-second bound and its focused test passes. No runtime
contract was weakened. The final root run must still verify the whole lane.

The initial static compile and Lean build/oracle/replay passed before refactoring.
Final static, umbrella and Lean runs are pending after final code changes. The durable
native STS decision document records limits and rejected fake-caller/prompt-only paths.
GPT-Live/Morse duplex opening support and carrier E remain open. No paid provider
requests, calls, commits, or carrier mutations occurred in this checkpoint.

## Duplex follow-up research while root verification runs

Applied the OpenAI Docs skill and fetched the official GPT-Live session guide after
an official-domain search. It directs greetings through session.instructions.append
with delegation_id null, sent once after session.started while real input audio keeps
running (including silence). Match session.instructions.appended by client_event_id;
acceptance is not proof of spoken wording/playback. session.commentary.append can
paraphrase. Exact spoken wording needs checked audio or an application-owned verified
clip. Source: https://developers.openai.com/api/docs/guides/live-conversations
(checked 2026-10-05, greeting/disclosure sections). No OpenAI account/API request made.

The existing GPT-Live spec describes commentary for opening, but this current official
instruction path is a better fit for engine-owned generated opening. It must retain
response-context/burst correlation and should not inject synthetic caller audio.
Fixed duplex support needs a bounded, independently validated speech boundary; a prompt
or commentary alone must not be labeled exact. No duplex implementation/test was changed
while this root run was in progress. This is useful starting evidence for the next slice.

## Final verification

All five root gates passed after final implementation/refactoring: mix format
--check-formatted; mix compile --warnings-as-errors; mix credo --strict (1,193 files,
no issues); mix deps.unlock --check-unused; mix test (3,134 tests, zero failures,
98 excluded, seed 269987). Per app: MCP 37/3 excluded, Providers 29, AgentRuntime 99/8,
Engine 1,872/65, Calls 130, Gateway 541/8, Artifacts 20, Persistence 210/12, Console 196/2.
The affected readiness fixture also passed in the root Engine suite. Final bin/verify-lean
passed its build, oracle consistency and Elixir replay (one replay test, seed 723925).
Local Markdown file targets and git diff --check pass. No paid lane was selected.

The turn-provider slice is accepted. D3 remains unchecked for GPT-Live/Morse duplex
opening and E remains unchecked for the three bounded carrier acceptance calls. The
index, milestone, harness status and native opening decision now reflect that scope
and evidence. No commit created; unrelated existing Wrangler labnotes preserved.
