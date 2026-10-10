# Agent speech-to-speech completion plan

> Relocated from `docs/agent-sts-completion-plan.md` on 2026-10-09. First recorded source commit: `fe4a5d126c87` (2026-09-27T03:00:02+00:00).
> Supporting plan/evidence companion. [agent-speech-to-speech](agent-speech-to-speech.md) owns current scope, implementation checklists and acceptance; [the index](index.md) owns order. This is not a new independently ordered milestone.
> This preserves the 2026-09-27 closure plan. D1–D3 are proposed scope decisions, not approvals implied by relocation. D4 preserves recorded user direction; reconciliation with older unchecked continuation wording remains open. Later configured Gemini acceptance supersedes the old selection gating. The prerequisite assumption that GPT-Live is fully accepted remains unsatisfied while checkpoint F is open.

Status: plan written 2026-09-27. It assumes
[the GPT-Live completion plan](gpt-live-completion-plan.md) is finished, which
means every task in
[GPT-Live speech-to-speech](gpt-live-speech-to-speech.md) is checked,
including its hosted check. It then lists what is still open in
[Agent speech-to-speech](agent-speech-to-speech.md) and puts that
work into ordered packages. The milestone stays the source of truth for scope
and acceptance. This plan says how to close it.

## How to use this plan

- Package 0 comes first. The milestone has many unchecked parent boxes whose
  children are all checked, or whose work was committed later without ticking
  the box. Until those are reconciled, nobody can tell real gaps from stale
  bookkeeping.
- Decision D1 must be answered before packages 7 to 9. Decisions D2 to D4 each
  gate one package. Record each answer as a scope amendment in the milestone's
  status section, as the milestone's discovery-first rule requires.
- Each package is one coherent commit, or two where noted. Each one leaves the
  umbrella green and ticks only the boxes whose acceptance passed. Follow
  `AGENTS.md`: red-green, focused tests while iterating, the five root gates
  before each commit, and `bin/verify-lean` for any change to a source-cutover
  or speech state machine.
- Start a fresh session for each package or two. Each package is written to be
  understood without this conversation.

## What the GPT-Live work already closes or changes

The GPT-Live packages touch shared capability and room code. When they are
done, the parent milestone gains the following, which package 0 must credit:

| GPT-Live work | Effect on the parent milestone |
| --- | --- |
| `hold` descriptor fact (`:stop` / `:mute`), `set_input_hold/2` | Gives the "reusable hold/release" tasks (lines ~1188 and ~1243) a contract shape: `:mute` providers keep their session, while `:stop` providers use fail-closed idle reuse. See D3. |
| Channel tombstone window, 17th-context admission (R11-1, R9-1) | Most of the "more than 16 sequential retired origin rotations without unbounded tombstones" task (line ~1914). Tool and response obligation holds still need their own proof. |
| Provider-originated transfer through the room (`d883ce13`, Amendment 2) | The transfer part of C's slice exit, for Morse STS and the fake GPT-Live socket. |
| Aligned spoken prefix, per-burst responses | The duplex providers only. Morse STS and Google keep the older one-output-per-reply path. |
| Duplex load mode in `call_load_test.exs` | Extends F's load lane. The parent's three original modes must still be rerun in the final pass. |
| Console `openai` entry with `s2s` enabled by user direction | Contradicts F's box that says "the Console setup catalog offers no `s2s`". Record an amendment: `s2s` is enabled for OpenAI by the user's 2026-09-26 direction and stays gated for Google. |
| Provider contract docs for duplex, hold and history | Most of F's documentation sync. Only the parent-specific additions in package 10 remain. |

The GPT-Live work does **not** close the following: the Google adapter (E),
agent-output STT with a hosted recognizer (D), room-level proofs for the
non-duplex Morse STS provider, native transports in every transcript mode, STS
tool bindings other than host and transfer, and the telephony compiled-room
cutover.

## Decisions needed

**D1: what happens to Google Gemini Live STS.** Checkpoint E has about 20 open
tasks. Several of them (streaming activity signals, interaction status,
cross-origin cutover, handle coverage, interrupted-history reconciliation) can
only be settled against the hosted service. The milestone's exit rule names
"Morse and the gated Google Live adapter".

- **Option A (recommended): move Google STS to its own milestone.** Keep the
  adapter in the tree, still unadvertised with `Registry.fetch_capability("google", :sts)`
  failing closed. Move E's open tasks and F's Google hosted check into a new
  "Google Live speech-to-speech" milestone. The parent then closes on Morse
  STS, Morse duplex and GPT-Live, which are already the hosted-proven path.
  This is a scope change and needs the user's approval, recorded as an
  amendment.
- **Option B: finish Google here.** Packages 7 to 9 below then apply, and the
  milestone cannot close without a billable Google hosted run.

**D2: agent-output STT with a hosted recognizer.** D's remaining open work is
the Deepgram Flux finite-input terminal proof (lines ~2138 to ~2171). It needs
a billable hosted probe. Admission already rejects hosted sidecars that lack a
finite-input terminal.

- **Recommended:** accept D with Morse output-STT plus explicit hosted
  rejection at admission, and move the Flux proof to a follow-up. The "Native
  speech with recognition" mode then works locally and fails closed for hosted
  recognizers.
- **Alternative:** run the prepared Flux CloseStream probe with billable
  authorization, then implement the finite tail flush (package 6b).

**D3: reusable hold for `hold: :stop` providers.** The open tasks ask for an
acknowledged provider input discard/reset so that a dirty hold can reuse the
session. With the new `hold` fact:

- **Recommended:** `:stop` means "reuse only when provably idle, otherwise
  retire and allocate fresh on release". The input discard/reset task becomes
  not applicable. Package 3 proves the fresh-allocation path in a compiled
  room, so a dirty hold never leaves a dead call.
- **Alternative:** implement provider input reset for Morse STS as well.

**D4: STS tool conversation semantics.** The
[tool execution model](../../docs/tool-execution-model.md) describes text agents: a
`running` acknowledgement, then a private continuation turn. STS providers
(Gemini, GPT-Live delegation) instead require exactly one native function
result per call.

Agreed direction (user, 2026-09-27):

- **Single result per call by default.** The provider receives one native
  result when the invocation ends, and that result is the continuation. The
  text model's running acknowledgement, continuation commit receipts and
  caller-turn blocking do not apply to STS, because the provider owns
  turn-taking. This closes the "parent coordination" task (line ~1829) as not
  applicable. Record it in `labnotes/milestones/sts-tool-lifecycle.md`.
- **Non-blocking is per model, using the best mechanism that model offers.**
  Use native asynchronous function calling where the model supports it (for
  example Gemini's `behavior: "NON_BLOCKING"` with `scheduling`). Otherwise
  use an available context append (for example GPT-Live
  `session.commentary.append` or `session.thinking.append`). Never send a
  late result as ordinary user text. The mechanism is a descriptor fact,
  provisionally `late_tool_results: :native_async | :context_append | :none`,
  and it is **per model, not per adapter module**. One provider can offer
  models with different support. Each adapter keeps a model profile table
  keyed by model ID, next to the wire code that implements each mechanism.
  Its configuration constructor (for example `GPTLive.new/1`) looks up the
  selected model's profile and rejects unknown models, and the descriptor
  reads the fact from that profile. Admission uses the same lookup through
  `CapabilityCatalog.validate_speech/2`, before any session starts. A runtime
  configuration flag cannot enable a mechanism the adapter has no wire code
  for. The engine owns everything that does not depend on
  the provider: delivery timing (wait for no open caller turn and no active
  output, bounded), size limits, fixed trust framing, and carrying pending
  calls across a reseed.
- **Review each integration case by case.** When a provider or model is
  integrated, review its documentation and record the mechanism in its profile
  doc (for example `docs/sts-duplex-profile.md`). Prove it in that provider's
  hosted check. Support differs by model, not just by provider: Google's Live
  tools page lists asynchronous function calling for Gemini 2.5 Flash Live but
  not yet for 3.1 Flash Live.
- **For this milestone:** every current adapter declares `:none`. A
  `non_blocking` binding on an agent whose provider declares `:none` is
  rejected at Call Spec admission with an explicit error. Implementing
  `:context_append` for GPT-Live is a follow-up item, not needed to close this
  milestone.

The package list assumes the recommended answer for each decision.

## Package order

| # | Package | Closes |
| --- | --- | --- |
| 0 | Reconcile the checklist against committed evidence | stale parent boxes (table below) |
| 1 | STS tool bindings: variable, platform, MCP; no silent `:deferred` | line ~1517 and its parent (~1464), ~1829 via D4 |
| 2 | Telephony compiled-room source cutover | ~1107, ~1124, telephony side of ~1033 |
| 3 | Hold/release lifecycle for `:stop` providers in compiled rooms | ~1174, ~1188, ~1243 via D3 |
| 4 | Morse STS room lifecycle exit (interruption, hold, transfer, owner loss) | C ~2022, C exit ~2031 |
| 5 | Native transport matrix in all transcript modes | B ~518, B exit ~552, ~659 |
| 6 | Agent-output STT exit | D ~2043, ~2068, ~2107, ~2121 (6b only with D2's alternative) |
| 7–9 | Google (only with D1 option B) | E |
| 10 | Room projections, examples and parent docs | F ~3223's named leftovers |
| 11 | Gateway handoff investigations | ~1538, ~1577, ~1681 |
| 12 | Final coordinated acceptance | F ~3152 (or its amendment), ~3223, index |

---

## Package 0: reconcile the checklist

Goal: every unchecked box is either ticked with cited evidence, re-scoped by an
amendment, or left open with a stated remaining gap. Change no code. This is a
documentation-only checkpoint. Verify each claim by reading the cited test or
commit, and run the cited focused test file once.

Candidates to tick after verification (line numbers are approximate, as of
`dd8736ea`):

| Line | Task | Evidence to verify |
| --- | --- | --- |
| ~693, ~699 | Room-controller design review and its prerequisites | `labnotes/20260923-0131-sts-external-room-control.md`, `labnotes/20260923-0243-sts-activity-provenance.md`; checked children at ~704–740 |
| ~741, ~748 | Producer-side activity provenance, emission stamps | `3e5f2ace` (native allocation generation fence), the checked children at ~752–800 |
| ~808, ~821, ~855, ~859 | Stale provider evidence, envelope generation, admission-time capture | `05b02718` ingress cutoff, `ea366efb`, `b9075c39`; the compiled-room cases in `sts_transcript_modes_test.exs` |
| ~874, ~885, ~899, ~912, ~929 | WebRTC raw RTP fence and acknowledged same-peer cutover | `eae445ae`, `b9075c39`, `fa8d9dc5`, `b06bf1c6` (fail closed on loss and deadline). Confirm that caller-side fail-closed is covered; if not, leave ~912 open with that single gap. |
| ~1028 | Bounded room-owned cutover state machine | `RoomAuthority.STSSourceCutover`, `b9075c39`, `a626b162` (STT kept when STS retired), Lean model in `verification/` |
| ~1033 | WebRTC compiled hold/reopen proof | `d785a1cb`, `ea366efb`; its telephony remainder moves to package 2 |
| ~1069 | Twilio/Telnyx raw media fence | `9427ad0b`, T1–T3 checked |
| ~1275, ~1348 | Human-STT activity wiring; external/hybrid admission and revoke/regrant | checked children at ~1281–1340, `4f375877`, `5d37ca5a`, `0f4ba651`, `bea75662` |
| ~1416 | Room-owned public IDs | all children checked except ~1464, which package 1 closes |
| ~1535 | Record focused evidence and commit | bookkeeping; tick |
| ~1914 | More than 16 retired origin rotations | `9700df3a`, `522f23ec` (R11-1, R9-1). Tick only if tool and response obligation holds are covered; otherwise re-scope the remainder into package 1. |
| ~1933 | Early response-event binding | `labnotes/20260922-2133-sts-response-start-grant.md` and its children. The cross-origin Google part moves to D1. |
| ~2084, ~2095 | Directional egress revocation and queued replies | all children checked |
| ~2281 | Output-STT registry and PCM negotiation | all children checked (`f9db3319`) |
| F Console box | "No `s2s` in setup" | Record the user's 2026-09-26 amendment for OpenAI; Google stays gated |

Record each decision (D1 to D4) as a milestone amendment in the same commit,
and then move the Google and Flux tasks under a "moved to follow-up" heading if
the recommended options are taken. Update the status section to a short current
summary. The long historical status paragraphs can move to a "status history"
subsection, so the top of the file says where the milestone stands now.

Acceptance: a reviewer can read the open-box list and see only real work.

## Package 1: STS tool bindings

Problem: `RoomAuthority.SpeechToSpeech.Tools.invocation_for/2` returns
`:deferred` for every binding that is not a blocking host tool or a
participant transfer. The provider's call then waits forever. The milestone
requires unsupported bindings to fail explicitly (line ~1517).

Work:

1. Red: a compiled Morse STS room with a Call Variables tool, an MCP tool and a
   `non_blocking` host tool. Each case currently produces no
   `ToolCallCompleted` or `ToolCallFailed`.
2. Reuse the text agent's binding resolution for STS. The text path builds
   its `InvocationBinding` in `agent_runtime/invocation_executor.ex` and
   `tool/invocation_binding.ex`. Route STS through the same constructor rather
   than adding STS-specific handlers.
3. Any binding the STS path cannot run fails at once with
   `{:error, :unsupported_binding}`. The provider receives a failure result,
   never silence. Delete the `:deferred` branch.
4. Per D4: add a per-model profile table to each STS adapter, carrying
   `late_tool_results` (`:none` for every current model). Build the
   descriptor fact from the selected model's profile, and reject `conversation_mode: :non_blocking` at Call
   Spec admission when the selected STS provider declares `:none`. Add an
   admission test.
5. Google adapter: answer a call the channel discards with a failure function
   response, as GPT-Live does (noted in GPT-Live review 11). Skip this if D1
   moves Google out; then record it in the Google milestone instead.

Tests: the three compiled-room cases above; argument schema rejection before
submission; a permission revoked between call and result produces no delivery
to a replaced source; an MCP tool against the existing `test/support/remote_mcp_fixture.ex` and
`remote_mcp_wire_server.ex`. Do not add a network test to the default lane.

Closes ~1517 and ~1464, and ~1829 through the D4 amendment.

## Package 2: telephony compiled-room source cutover

Goal: the telephony analogue of `d785a1cb`. The `MediaSession` hold/arm
boundary exists (`ebeaef8f`). What is missing is the end-to-end room proof.

Work: in the Call Engine room tests, use a telephony-shaped test connection
with `source_control?: true`, or drive a real `MediaSession` from a Gateway
test with the Twilio test socket. Prove the following in order: a policy
cutover holds the socket epoch; the old selected STT is retired; the fresh STT
origin binds; arm; reopen; a frame queued before the hold is dropped; a fresh
frame reaches STS; marks stay responsive throughout. Add a timeout case (the
room fails closed and input stays held) and an overlapping transfer hold.

Owner: Gateway for the socket half and Call Engine for the room half. If one
test cannot span both, write one test per side and a contract test on the
message shapes between them. Run `bin/verify-lean`, because the source gate has
a Lean model.

Closes ~1107 and ~1124, and the telephony remainder of ~1033.

## Package 3: hold/release for `:stop` providers

Per D3. Today a dirty hold on Morse STS or Google stops the capability with
`:unsafe_hold`, and an idle hold reuses it. What is still unproven is that the
call continues afterwards.

Work:

1. Red, in a compiled Morse STS room with external control: caller `HI` is
   accepted, then a hold, then a release. Require that the old reply is never
   played, that a new STS allocation starts after release (the room already
   recreates the capability in source cutover; reuse that path), and that a
   new `HI` produces `RECEIVED HI`.
2. The same with a transfer hold instead of a policy hold, and with hybrid and
   provider control.
3. Prove the producer boundary from ~1174: an STT boundary emitted before the
   hold and one first delivered after it cannot control the new epoch. This
   probably passes already through the allocation-generation fence; if so, the
   test is the evidence.

Record in the speech provider contract that `hold: :stop` means idle reuse or
fail-closed replacement, and that providers need no input reset callback.

Closes ~1174, ~1188 and ~1243 (the last one through the amendment).

## Package 4: Morse STS room lifecycle exit

Goal: C's controller claim (~2022) and slice exit (~2031) for the classic,
non-duplex Morse STS provider. GPT-Live package 5 proves the same for Morse
duplex; this package mirrors it.

Add cases to `sts_call_test.exs`, or a new `sts_lifecycle_call_test.exs`:

1. Interruption: caller speech during a reply gives exactly one terminal agent
   turn outcome and zero playback after the fence.
2. Output-only egress revocation mid-reply: a single terminal outcome, provider
   credit returned, and the next reply works after regrant (the capability
   proof exists; this is the room proof).
3. A second source connection is rejected with `:source_mismatch`.
4. Hold with a tool in flight: the tool result is retained, and old speech is
   not revived after release.
5. Transfer committed and transfer failed from a provider-originated call
   (reuse `d883ce13`'s cases if they already run on Morse STS; cite them).
6. Owner loss: kill the room owner and assert `:DOWN` for the capability tree,
   the invocation workers and the provider.
7. Bounded commands: more than 16 queued commands fail explicitly rather than
   growing the queue.

Closes ~2022 and ~2031.

## Package 5: native transport matrix

Goal: B's room proof (~518) and exit (~552) require native calls, not only the
embedded PCM connection. The caller-turn publication task (~659) is also still
open for native sources.

Work, in Gateway integration tests (the local HTTP WebRTC lane and the
telephony media-session tests):

- WebRTC: a real `ExWebRTC` peer sends Opus Morse `HI` to a room with Morse
  STS, in each of the four transcript-source modes. Assert one caller pair, one
  agent transcript after playback settlement, and decoded agent audio received
  at the peer.
- Telephony: the same over a Twilio (PCMU) and a Telnyx test socket, in at
  least the provider-transcript mode and the human-STT mode.
- In one WebRTC case, assert that published events contain only room-owned IDs
  (no `inspect(ref)` values) and that nothing from a second room appears.
- Rerun the old LLM + TTS native tests unchanged.

Bound the matrix: four WebRTC modes plus two telephony modes per carrier. Tag
the cases like the existing native lanes if they are slow.

Closes ~518, ~552 and ~659 (including the external/hybrid subtask ~689, once
package 0 has ticked its children).

## Package 6: agent-output STT exit

With D2's recommended option:

1. Red: a Morse STS variant that declares no output transcription fails
   selection without `output_speech_to_text`. With it, exactly one agent
   transcript is produced, in a compiled room. Most of this exists in
   `sts_transcript_modes_test.exs`; add whatever the declaring-no-transcription
   variant lacks.
2. The D exit cases in one compiled room file: complete, interrupted, denied
   policy, STT failure, slow consumer, the delayed-final-after-timeout case, and
   a multi-segment reply. Most exist at the capability boundary; the room
   versions are the gap.
3. Admission rejects Deepgram and Google as output recognizers with a clear
   error, and the author guide says so.

**6b (only with D2's alternative):** run the Flux probe with billable
authorization, then implement the finite tail flush and one terminal marker
(~2167).

Closes ~2043, ~2068, ~2107 and ~2121. ~2138, ~2144 and ~2167 move to the
follow-up.

## Packages 7–9: Google (only with D1 option B)

Summarised here, because the recommendation is to move them out. Each is
large enough to need its own detailed plan.

- **7. Controller streaming and activity:** ~2396, ~2427, ~2433. Drive the
  fake socket through the real controller with the raw `voiceActivity`
  profile; output streams before `turnComplete`.
- **8. Response ownership and continuity:** ~2463 to ~2817 and ~2845. This
  covers caller and response associations, the input-transcription profile,
  `interactionStatus`, the response-state owner, cross-origin cutover after
  `IDLE`, and handle coverage. Several subtasks ask whether the wire *can*
  behave a certain way; only the hosted run answers that.
- **9. Interruption history and hosted check:** ~2878, ~2889, ~2936, ~2960,
  ~2979, ~3049, and F ~3152. Build a tagged hosted lane like
  `labnotes/milestones/gpt-live-hosted-check.md`, then run it with billable authorization.

## Package 10: room projections, examples and parent docs

F's final box names four leftovers besides the gates:

- **RoomAuthority-level publication:** check that `EventPublisher` and
  `TranscriptRouter` handle STS agent and caller events like text-agent
  events: archive, live routes and retention settings. Add one compiled-room
  test per route kind if coverage is missing.
- **Transfer/hold/teardown plumbing:** packages 2 to 4 cover this. Cite them.
- **STS usage and history projections:** the call-details publication and
  operator inspection show STS usage (provider, voice-seconds, output-STT) and
  the transcript. Add a presenter test and inspect the rendered call-details
  page with `agent-browser` at desktop and mobile widths.
- **Call-spec and API examples:** add an STS agent example for each of the
  three modes to the call-spec docs and the docs site. Run the docs-site
  `node --test` lane.

Update `docs/speech-integration-guide.md` with the D3 and D4 rules.

## Package 11: Gateway handoff investigations

Three open tasks (~1538, ~1577, ~1681) come from `HumanTransferWebRTCTest`
failures on 2026-09-22. Root runs since then have passed (for example
`a626b162`: 2,690 tests, zero failures; `d883ce13`: 2,859, zero failures).

Work: run the file 20 times with seed 0 and a second seed under the usual
umbrella load (in parallel with the Call Engine suite), and record the
results. If nothing fails, close the three tasks with that evidence under the
rule the milestone already uses for the `SpeechToSpeechOutputSTTTest` case:
reopen only on a captured repeat. If one fails, capture the stage and handoff
result as ~1681 describes before changing anything.

## Package 12: final coordinated acceptance

Run this once, after packages 0 to 11:

1. The measured ten-call load lane in a quiet window, all modes (the three
   parent modes plus duplex). Keep the JSON lines in the labnote.
2. A rendered UI pass with `agent-browser`: the Console setup (OpenAI `s2s`
   on, Google off), service binding for an STS agent, and call inspection of
   an STS call. Desktop and mobile widths.
3. An independent implementation review of the whole milestone diff since
   `a31a479f`, by subagents. Fix findings through `bin/teammate` in the `vxpag`
   session, then review again.
4. All five root gates and `bin/verify-lean`.
5. The hosted gate: with D1 option A, the parent's hosted item is satisfied by
   the GPT-Live hosted check (already required by that milestone) and the
   Google item moves out. With option B, run package 9's check.
6. Tick the index entry only when every box that remains in scope is checked.

## Risks

- Package 0 may find that some "stale" boxes have a real residual gap, most
  likely ~912 (caller-side fail-closed) and ~1914 (tool obligation holds). Keep
  the gap open and small instead of ticking the parent.
- Package 5's native matrix is the slowest to run and the most exposed to
  timing flakes. Use explicit barriers and the existing native helpers; never
  widen deadlines without a contract reason.
- Package 1 touches the shared tool path used by text agents. Their suites
  must stay green, and binding resolution must stay in one place.
- If D1 option B is chosen, the milestone cannot close without a billable
  Google run, and parts of package 8 may turn out to be impossible on the real
  wire. Plan for a partial-support outcome, with explicit rejection of the
  unsupported control profiles.
