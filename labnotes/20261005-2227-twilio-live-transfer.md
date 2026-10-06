# Twilio live transfer acceptance

## Scope and checkpoints

The active objective explicitly includes the original Twilio milestone. The previous
completion audit proved outgoing-calls A–E, but omitted Twilio private-transfer and
selective-disconnect acceptance. That narrower completion claim is superseded.

- [ ] T1: build a focused encrypted three-room fixture; verify publication, portable
  participant contracts, controlled destinations, private briefing and bounded timers locally.
- [ ] T2: add a selected real Twilio private-transfer lane: Telnyx caller → Twilio
  reception → Twilio destination leg → Telnyx receiver. Require remote private briefing,
  destination carrier DTMF, main-room admission and reciprocal human speech through mixing.
- [ ] T3: terminate only the destination carrier leg and verify caller/room retention;
  then clean all owned rooms/legs and verify durable archive closure.
- [ ] T4: run focused conformance and required root gates; update both milestone/index
  and harness documentation with exact local/live coverage and remaining limits.

## Decisions and current evidence

Prior live runs prove both carrier directions and initial-call hangup, plus Twilio
no-answer. Original Gateway live tests assert accepted REST dial only; neither observes
media. Existing signed fake harnesses cover transfer, AMD, callback ordering, protected
destinations, privacy and recovery. The new paid lane must exercise real destination
press-1 rather than injecting a normalized Event. Telnyx's send_dtmf command can produce
real remote tones; Twilio bidirectional streams deliver inbound_track dtmf events.
Sources: https://developers.telnyx.com/api-reference/call-commands/send-dtmf and
https://www.twilio.com/docs/voice/media-streams/websocket-messages.

Use existing provisioned numbers and runner only; no new purchases or automatic redial.
Register cleanup before paid submission. Never inspect the live env file directly.
Pushnotify sent the resumption/checkpoint update successfully. Worktree has substantial
previous goal changes; preserve them and the unrelated cache labnote. No commits requested.

## T1 source builder and environment barrier

Wrote the initial encrypted-publication test before implementation. Its Mix invocation
failed before ExUnit: Mix.PubSub could not open its TCP subscription socket (`eperm`).
This is not red behavior evidence. Removed that unexecuted addition and wrote the smaller
pure three-spec contract test. Direct Elixir/ExUnit ran it and failed with the expected
undefined transfer_sources/1 (seed 286843). Implemented the source builder using the
existing fixture's speech/media schema. The first green attempt still failed validation
because the direct process had not started ReqLLM's model registry. Starting ReqLLM through
its ordinary application API made the test pass: one test, zero failures, seed 583901.
No model/speech or carrier request was made. Temporary compiled fixture beams live only
under /tmp; there is no replacement of Mix internals or sandbox bypass.

A temporary direct-Elixir runner loads ordinary test config and starts test applications
without enabling any network listener. Existing database fixture cases nevertheless fail
before assertions: PostgreSQL's Unix-socket connection returns `eperm`, then ownership
checkout expires. Result: five tests, four setup failures, five excluded, seed 10695;
the new pure case is green. These setup failures are not claimed as project regressions.
A direct Python socket probe also confirms TCP and Unix socket binds are denied.

## Selective destination disconnect conformance

The direct-Elixir signed two-carrier/decoder/ingress group passes 55 tests, zero failures
(seed 964808). Existing fake speech and REST boundaries require no sockets or database.
Added a focused post-bridge assertion to Twilio's silent-wait harness variant: authenticate
and correlate the destination stop frame, observe normal leg DOWN and media subtree DOWN,
retain caller main admission and joined state, observe no room DOWN and no redundant or
unrelated carrier hangup. The complete Twilio harness passes 14 tests/zero failures (seed 884088).
This is additional coverage of existing behavior; no production hangup policy changed.
This is local evidence only; real selective carrier disconnect is still required in T3.

## Common gates and scope accounting

Attempted all five common root gates. Compilation, strict Credo and mix test fail before
execution on Mix.PubSub socket denial; unused-dependency checking fails acquiring its
TCP lock. Formatting runs without that socket and found only the new assertion formatting,
which was corrected with the normal formatter. The root format recheck passes. Documentation checks pass 134 local links and balanced fences; git diff --check also passes.
No source-cutover or speech state-machine change was made in this checkpoint.
The active goal was inspected and remains active; no completion or blocked status issued.
The previous coverage audit is progress because it established that the Twilio milestone's
private-transfer requirement was not proved by the initial-call live tests.
This continuation adds authoritative local source/conformance evidence, not only a plan.

Corrected the milestone index's claim that only the old REST lane remained: real private
transfer and selective-disconnect acceptance remain, not merely a legacy test selection.
The Twilio milestone and harness decision record track T1–T4 separately from completed A–E.
No new paid call, purchase, credential-file access, commit, or account change occurred.
A second pushnotify progress update was delivered successfully, reporting the local
conformance evidence and execution barrier.

## Continuation: selected transfer lane and peer controls

Previous turn classification: progress (fixture source and selective fake disconnect
evidence). This second continuation revalidated the same environment barrier: creating
a local TCP socket now fails with PermissionError/eperm before bind. No live process
handle was outstanding; the preceding test sessions were terminal.

Added LiveTelephonyPeer with exact tenant/call/room/incarnation/participant/service/application
checks against an authorized media binding. Its private control token and key are excluded
from Inspect. Commands address only the encoded Telnyx control ID, do not redirect or retry,
and discard raw error bodies. The focused test initially failed on the missing module
(four failures, seed 371931). The first green attempt found a malformed apply/3 argument
list in the test (a tuple rather than a keyword list); corrected the test and all four cases
pass (seed 219113). These are synthetic Req.Test requests, not real carrier commands.

Added transfer publication over the existing publication function, with a test-owned
publisher seam verifying all three sources. Red: missing publish_transfer/2 (seed 586758).
The existing encrypted Calls storage path remains the default; that path is not verified
in the current sandbox. Added a private socket-owner Registry for exact bindings, while
delegating all carrier WebSock callbacks to the existing observed production sockets.
Red: missing socket module (seed 904429). An initial cleanup test raced Registry's asynchronous
cleanup after process DOWN. Removed that dependency-guarantee test rather than adding sleeps
or changing runtime semantics. Kept project-owned lookup and duplicate-replacement rejection.

Added a deterministic model fixture: opposing Alpha/Bravo speech and exactly one reception
transfer tool request with reason Delta. This bounds the new case to the caller dial and
one transfer dial, with no extra hosted LLM request. Its model test was red on the missing
module (seed 297638). The proposed empty follow-up response violates the existing
ModelResponse contract; changed the desired fixture follow-up to Charlie with no tools.
The transfer spec's local model selection was separately red against the former Google
selection (seed 486041), then changed only these transfer sources. Original initial-call
live cases retain real Gemini inference. Added the owning Console test-only AgentRuntime
dependency; no package version or lockfile change is needed.

The full new component group passes 10 tests/zero failures (seed 919938): source schema and
publication, peer REST boundary, private binding lookup/duplicate protection, and one-shot
model behavior. Compiled the new live integration module directly against existing compiled
dependencies with zero compile/runtime diagnostics. The first compiler invocation emitted
a tool-API deprecation warning; the corrected return_diagnostics invocation has no warnings.
This is not an umbrella compilation gate and does not execute the live case.

Implemented the excluded live_telephony_transfer case in the existing assembled Console
lane. It requires remote Delta at the destination, no Delta transcript at the caller,
private transfer-preparation readiness, real Telnyx send_dtmf press-1, main admission,
reciprocal Alpha/Bravo across the human bridge, one completed transfer, and exactly three
call records. It then terminates the exact destination via Telnyx and monitors destination,
Twilio support leg and media DOWN while caller/reception stay live; final reception cleanup
must close all three rooms/archives. Binding values stay in the private Registry, not logs.
The negative transcript check is bounded evidence; exact privacy/frame isolation still has
the existing local conformance coverage. The new live scenario has not run.

Reattempted all common gates after the new code/dependency declaration. Formatting passes.
Compilation, Credo and mix test stop on PubSub socket eperm; unused-dependency checking stops
on its TCP lock. No policy escalation, direct credential-file access, new paid call,
resource purchase, account change or commit was attempted. Original T1–T4 acceptance remains
unchecked until assembled/live evidence and common gates exist. Goal remains active.

## Final stimulus correction and checkpoint evidence

Source review found a gap before any paid attempt: both initial markers can finish while
transfer is private, leaving the new human bridge silent until idle notification. Added a
single destination Bravo stimulus through the existing Telnyx call-control speak command.
Official current documentation permits female voice for basic en-US text, an explicit
self target, and a single loop. Source:
https://developers.telnyx.com/api-reference/call-commands/speak-text. The test peer sends
only six fixed characters, never arbitrary text or a different control ID. This extra
carrier-native TTS command may incur charges when the selected case runs; no additional
LLM request or carrier dial is introduced. It is a handset test stimulus, not a new
application TTS provider. Telnyx speak callbacks are already authenticated then ignored
as unconsumed events by the existing decoder.

The marker command test failed on missing say_bravo/2 before implementation (five tests,
one failure). The complete component group now passes 11 tests/zero failures, seed 466420.
The live case invokes the marker only after support main admission and rejects Bravo at
the caller or Alpha at the destination before press-1, alongside private Delta checks.
Those phase checks reduce the chance of old/private audio satisfying the bridge proof.
No live scenario has run, and no overall acceptance checkbox is closed on these assertions
merely being written. Final direct compilation of all four support modules and the live integration module passes with zero compile/runtime diagnostics. Root formatting, 134 local documentation links/fences and git diff --check pass. Progress pushnotify was delivered successfully. Four root gates and the selected live case remain unverified because the socket/DB restriction persists.

## Third-turn blocked audit

Previous turn classification: progress. It implemented the selected transfer case and
its peer/model/publication components, passed 11 focused tests, compiled the current
support/integration sources without diagnostics, and recorded the remaining acceptance.

This is the third consecutive goal turn encountering the same socket/DB execution barrier.
A fresh local TCP probe returns errno 1, and fresh mix compile --warnings-as-errors fails
before compilation because Mix.PubSub cannot open its TCP socket (eperm). The execution
policy permits no escalation in this session. There is no outstanding live process/test
handle to wait for, and no unimplemented local component remains that could establish
the missing live evidence without sockets, the database, and carrier-reachable ingress.

Completion audit against the full objective:
- Outgoing-calls A–E retain their recorded bidirectional/live no-answer and original
  root-gate evidence; this is historical acceptance, not a new run of the current tree.
- The original Twilio milestone still has unchecked live audio/disconnect acceptance,
  common gates and completion tasks. The implemented transfer assertions are not proof
  that the selected carrier scenario ran.
- T1's encrypted assembled publication remains unverified in this session; component
  publication/schema checks pass but do not replace real database execution.
- T2/T3 real private transfer, destination DTMF, bridge speech, selective disconnect and
  three archive closures require the selected live_telephony_transfer run.
- T4 formatting/documentation checks pass; compile, Credo, umbrella tests and unused
  dependency checks remain unverified because their socket/lock setup fails.

Further fake runs, REST-only dial tests, or narrower checks cannot close those requirements.
No new paid call or purchase is justified while the endpoint/database cannot start.
The next action is to run the selected transfer case and common gates from an execution
session permitting local TCP/Unix sockets and database access, using the existing runner
and provisioned resources. Goal status must now be blocked, not complete or paused.
The original objective and all pending acceptance requirements remain intact.
