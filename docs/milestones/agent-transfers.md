# Allowlisted agent-to-agent transfers

Status: complete as of 2026-09-11. Specification review: approved (2026-09-08).
Prerequisites: [Remote MCP tools](remote-mcp-tools.md); [Call lifecycle](opening-audio-and-call-lifecycle.md).
Sources: [Transfer identities](../../labnotes/20260905-0405-call-definition-design.md#runtime-participant-and-transfer-identities); [transfer success/failure](../../labnotes/20260905-0405-call-definition-design.md#transfer-success-and-failure--approved-g8-baseline); [history policies](../../labnotes/20260905-0405-call-definition-design.md#initial-agent-transfer-history-policies).

## Runnable outcome

A reception agent transfers the caller to a billing agent. Billing receives only permitted variables/spoken history, the call identity and variables survive, and reception stops only after billing is ready and the room commits.

## Specification

- Derive the transfer tool from the source's simple transfers list; no list means no tool. Model receives allowed participant refs/safe descriptions, never arbitrary runtime targets/numbers/URLs. Reject alias collisions and enforce allowlist/current source activation again at execution and room commit.
- One participant identity per definition key per call; re-entry uses that identity with a fresh activation. Pinned entry refs do not change. Destination preparation starts only needed capabilities; it is not admission or conversational ownership.
- Room-authorized prepare/commit keeps source responsible until destination conversation/capabilities are ready. Emit completed only after successful control/routing commit; then terminate the entire source execution subtree. Submitted CallVariables requests may finish independently.
- Shared transfer_policy has one configurable 30s total attempt budget; phases do not reset it. Failure/timeout terminates destination attempt and returns a typed outcome to the source; late callbacks cannot commit or revive old output.
- If permitted source capabilities need restoration, allow exactly one bounded attempt; restart loops cannot reset it. If none works and no usable conversation remains, end. Detailed cause stays internal even with full sample tool visibility; public/agent outcomes are generic.
- Support approved fresh/all_spoken/last_n_spoken/selected history projections without summarization. Include only permitted confirmed user/played assistant utterances and destination-readable variables, never system prompts, hidden tools/scratch state, or generated-but-unplayed text. Re-entry does not replay first greeting.
- This slice runs agent destinations under its supported media policy. Reject presence-route combinations not enforceable until the mixing slice; never ignore privacy at transfer. Later human adapters use the same engine contract, not a named-transfer workflow.

History modes are closed: fresh has no prior model history; all_spoken contains permitted
confirmed user/played assistant utterances; last_n_spoken bounds that completed-spoken window;
selected sends no history, only allowlisted typed variables and an explicit reason. Destination
preparation may become ready but greeting/TTS/main output stays inaudible to the caller until
commit. The source retains responsibility; because the generated transfer binding is
default-blocking, later caller turns receive the platform hold response rather than entering either
agent's LLM until the transfer reaches a terminal continuation.

## Implementation checklist

- [x] Red-test compiler-derived transfer schema/aliases and runtime source/target authorization.
- [x] Implement room prepare/commit lifecycle, distinct participant/activation identities, and supervised destination/source ownership.
- [x] Integrate private destination history/variable projection and source termination after commit.
- [x] Preserve a re-entering agent's participant identity while creating a fresh activation and rebinding its private tool authority.
- [x] Implement total deadline, late-result exclusion, typed failures and single restoration budget.
- [x] Emit private transfer history and safe client outcomes without adding new RTVI-core messages.

## Acceptance and failure checks

- [x] Allowed transfer succeeds; injected target, wrong/stale source, duplicate preparations, and generated-tool alias collision fail before unauthorized startup.
- [x] Destination startup fails or deadline expires: source remains responsible, no completed event, destination cleaned up.
- [x] Commit preserves call/variables/entry refs; source capability/tool workers terminate, old output cannot reach new activation.
- [x] Re-enter agent: same participant ID, new activation, no greeting replay; permitted history only.
- [x] Restoration attempts exactly once; detailed failure does not leak through speech or full-debug events.
- [x] Empty transfers expose no tool. Every history mode excludes private prompts/tool data
  and generated-but-unplayed text; selected contains only allowed variables/reason.
- [x] Block destination preparation: source retains responsibility and serves the configured
  blocking hold; destination cannot speak to the caller.
- [x] One 30s budget starts at accepted preparation across all phases; failed-commit/deadline
  races and late completion produce no transfer.completed event or stale destination output.

## Manual verification

1. Use caller/reception/billing catalog and synthetic protected order variables.
2. Ask reception to transfer; compare identities, variables and billing's allowed history.
3. Exercise a failing destination and controlled deadline; confirm reception handles the outcome.
4. Try an unauthorized destination and re-entry; inspect safe events and no stale speech.

## Scope boundaries

No human bridge, arbitrary dialing, named transfers, graph/on_success hooks, generalized concurrent consultation, transfer-history summarizer, or caller reconnection. Presence-driven media is implemented next, not silently bypassed here.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Partial implementation evidence (2026-09-10): schema `20260910.04` accepts unique, non-empty
definition-local agent transfer refs and rejects malformed, duplicate, missing, self, and human
destinations with indexed paths. The compiler derives one `transfer` descriptor only for a
non-empty list, keeps runtime participant/activation identities in its private binding, projects
only safe refs/descriptions, validates the destination with a closed JSON Schema, applies the
ordinary participant-local visibility override, and pins conversation admission to `blocking`.
Both conversation modes retain the common independently supervised worker contract; this derived
tool adds no inline execution route. Authored `transfer` aliases remain reserved. `PlanStartup`
still rejects all transfer-enabled plans, so this checkpoint cannot start a destination or mutate
room control before the prepare/commit implementation exists. Four focused transfer compiler tests,
the 18-test compiler/descriptor/startup group, and the complete 263-test Call Engine suite passed;
Calls, Gateway, and Console passed 36, 66, and 57 tests respectively.

The next red/green checkpoint added the first runnable fresh-history transfer. A model-issued
`transfer(destination)` runs in the ordinary activation-owned invocation worker. Room Authority
then reauthorizes the exact room/incarnation, attached caller, current source participant and
activation, immutable allowlist, and pinned destination identity. It prepares the destination
participant/runtime and selected TTS before changing active routing; after commit it emits one safe
completion using the existing tool event, tears down the complete source participant subtree, and
routes the next caller turn through the destination prompt. The same room and Call Variables
process survive. A focused stale-source case proves rejection before destination startup. The two
focused room tests and the complete 265-test Call Engine suite passed with one tagged integration
exclusion. This does not yet prove preparation failure/timeout, restoration, late exclusion,
re-entry, or the non-fresh history projections.

Schema `20260910.05` adds a closed call-level `transfer_policy.attempt_timeout_ms`, defaults it to
30 seconds, validates 1–120 seconds, and pins it into the immutable plan. Transfer-capable
activations enlarge the ordinary supervised invocation timeout only when needed so it encloses the
pinned transfer budget by one second; execution remains in the same activation-owned tool worker.
Six focused compiler tests pass.

Destination materialization now runs under a separately named, room-owned task supervisor rather
than inside Room Authority. Room Authority starts one monotonic total deadline before task startup,
remains responsive while the destination model/runtime, participant subtree, and selected TTS are
prepared, and reauthorizes the source immediately before commit. Failure, task death, deadline
expiry, or stale commit authority keeps the source active and removes the exact destination
participant/TTS preparation. A late task result cannot commit after pending-attempt authority is
cleared. A second request while preparation is pending is rejected before another task starts.

The failure and deadline room tests use controlled destination-provider setup. They prove generic
tool failure, source continuity, a responsive blocking hold while preparation is pending, absence
of destination registration, duplicate-attempt rejection, and no completion after releasing expired
setup. The four focused room tests pass. The combined restoration/history/re-entry checklist items
remain open; this checkpoint does not claim those behaviors.

Schema `20260910.06` adds the destination-owned inbound `transfer_history` contract while keeping
source allowlists as simple participant-ref arrays. Omission pins `fresh`; the other closed modes are
`all_spoken`, `last_n_spoken` with a positive required `turns` value, and `selected`. Unsupported
modes, missing/invalid `turns`, and a `turns` value on another mode fail at the exact definition
path. The focused compiler file passes eight tests and the complete Call Engine suite passes 271
tests with one tagged integration exclusion. Runtime projection remains open, so the combined
history checklist item is not checked.

Agent Runtime now has the narrow seed boundary needed by the runtime projection checkpoint. A
session may start with validated plain caller-user and tool-free assistant messages after its own
system prompt; injected system/engine/tool messages, tool calls, and tool metadata are rejected.
The focused seven-test Session file and complete 53-test Agent Runtime suite pass with two tagged
integration exclusions. That internal prerequisite alone did not populate the option or claim a
transfer-history acceptance item.

Call Engine now owns a private room transcript projection and populates the seed boundary at the
start of destination preparation. Accepted caller text/final STT is recorded as user history;
assistant text is recorded only after audio-sink playback completion. `all_spoken` and
`last_n_spoken` therefore carry confirmed delivery facts while generated-but-unplayed output is
excluded; `fresh` and `selected` carry no prior messages. The projection is snapshotted once per
attempt and its inspection surface exposes only its size. A focused room transfer proves two prior
caller inputs reach billing while an unplayed generated response does not. The six transfer-room
tests and one pure projection test pass, and the complete Call Engine suite passes 273 tests with one
tagged integration exclusion. Selected reason/variable packet semantics and complete re-entry
coverage remain open.

The selected-history transfer descriptor now expresses its destination-specific reason contract.
For a selected destination it requires exactly `destination` plus a non-empty reason bounded to
1,024 characters; ordinary destinations continue to accept only `destination`. The private request
boundary independently rejects missing, blank, oversized, extra, or destination-inappropriate
reason input and retains the normalized reason outside its inspection surface. The focused
compiler/room transfer run passes 15 tests and the complete Call Engine suite passes 275 tests with
one tagged integration exclusion. This checkpoint captures authority-bearing input only; it does
not yet claim destination model-context or Call Variables delivery.

Agent Runtime now provides the provider-neutral transient context seam required for that delivery.
An optional host source is refreshed before every generation, independently bounded by timeout and
encoded size, restricted to a JSON object, and excluded from committed conversation. ReqLLM merges
it with current pending-invocation state in the existing trusted state envelope rather than
creating a caller or history message. Sixteen focused source, Session, and ReqLLM projection tests
pass; the complete Agent Runtime suite passes 58 tests with two tagged integration exclusions. That
provider-neutral checkpoint did not itself claim Call Engine delivery.

Call Engine now supplies that source for every agent with readable variables and adds the private
reason only when preparing a selected-history destination. The source delegates each fresh read to
the existing permission-enforcing Call Variables binding; it does not hold another mutable snapshot
or ask Room Authority to authorize values. A selected transfer integration proves the destination
receives only its readable order section and reason, with no prior source conversation or
reception-only variable. The existing variable-tool room flow proves a later completion generation
observes the newly accepted value and revision. The source and ModelRequest inspection surfaces do
not expose the reason. Twenty-five focused room tests and the complete 276-test Call Engine suite
pass, each with one tagged integration exclusion where applicable. Selected model-context delivery
is complete; re-entry and restoration remain open.

Agent re-entry now uses room-incarnation state to distinguish a participant's first activation from
a later activation. The immutable plan continues to pin one participant ID per definition key, while
each re-entry materializes a fresh activation ID and rebinds activation-local transfer authority.
Room authorization compares a request with the current active capability and the plan's stable
participant/allowlist data; it no longer treats the plan's first activation ID as permanent.

The focused room flow transfers reception to billing and back, then proves reception retains its
participant ID, its original activation is absent, a fresh activation owns the session, its
destination-owned `last_n_spoken` projection contains only the permitted trailing utterance, and
its rebound transfer tool can authorize another transfer. Participant lifecycle also rebinds the
archive recorder before the join fact, so the fresh activation—not the plan's first activation—is
used for re-entry and subsequent participant facts. The eight transfer-room tests pass.
Automatic first-message behavior for a transferred participant and explicit no-replay coverage are
still pending, so the combined re-entry acceptance checkbox remains open. The complete Call Engine
suite passes 277 tests with one tagged integration exclusion. Umbrella formatting,
warnings-as-errors compilation, strict Credo, and unused-dependency checks pass; umbrella tests stop
at the unchanged missing PostgreSQL SCRAM password before the database-backed suites begin.

Transferred participants now use the same first-message owner as the entry receiver. The room pins
whether a destination is entering its first committed activation before asynchronous preparation;
after control commit, `wait_for_input`, fixed, or generated behavior starts against the attached
entry caller. A later activation installs a completed first-message state with the same caller target
instead of replaying the configured greeting. The re-entry room flow observes billing's fixed
greeting on first activation and no greeting when billing is entered again. Together with stable
identity, fresh activation, archive attribution, rebound authority, and permitted-history checks,
this completes the re-entry acceptance item. The complete Call Engine suite remains green at 277
tests with one tagged integration exclusion; root formatting, warnings-as-errors compilation,
strict Credo, and unused-dependency checks pass. Root tests stop at the unchanged missing
PostgreSQL SCRAM password before database-backed suites begin.

The transfer event-boundary checkpoint adds private, protocol-neutral
`participant_transfer_started`, `participant_transfer_completed`, and
`participant_transfer_failed` archive facts. These facts originate only after room authorization,
retain the source participant and activation plus caller, invocation, and destination identities,
and distinguish closed internal preparation causes such as destination-plan unavailability and
total-deadline expiry. They are separate from the ordinary model-facing tool lifecycle, so no new
RTVI-core message or client authority was introduced. The successful and failed room flows prove
the private facts and their activation attribution; the controlled deadline flow proves its
distinct internal cause. Gateway full visibility now forces every `transfer` tool failure to the
generic `tool_failed` result even if a future engine event accidentally carries an internal atom.
The focused Call Engine transfer file passes eight tests and the focused Gateway projection file
passes four tests. A Calls-owned projection test proves all three private fact kinds cross the
engine/storage boundary instead of being dropped by its closed vocabulary; the complete Calls suite
passes 37 tests. The complete Call Engine suite passes 277 tests with one tagged integration
exclusion, and Gateway passes 67 with four exclusions. Root formatting, warnings-as-errors
compilation, strict Credo, and unused-dependency checks pass. Root tests stop at the unchanged
missing PostgreSQL SCRAM password before the database-backed suites begin. The source-restoration
checkpoint below completes the remaining single-attempt budget.

The source-restoration checkpoint retains the active agent's resolved TTS runtime independently
from its temporary capability process. If that capability disappears while destination preparation
is pending and the transfer then fails, Room Authority leaves startup to one room-supervised task
with a fixed 750 ms restoration budget. This stays within the transfer tool's existing one-second
envelope beyond the authored attempt deadline instead of creating a second unbounded phase.
Successful restoration installs a freshly monitored source TTS capability before the transfer
worker receives its generic failure. Failure, task death, or
expiry records one terminal restoration outcome and never starts another attempt. A source whose
speech capability remains present performs no restoration. The retained runtime changes only after
a successful transfer commit, so a later source uses its own pinned voice/provider selection.

The focused room test disconnects source TTS during controlled failing destination preparation,
observes exactly one replacement transport before the generic `tool_failed` event, and verifies the
private failed-transfer fact records `restoration: completed`. Disconnecting the replacement starts
no third transport. Existing failed and deadline attempts now record `restoration: not_required`;
the internal failure cause remains absent from the model/client event. A separate inspection test
proves the retained runtime exposes neither provider nor transport credentials in crash-state
formatting. The nine-test transfer-room file and complete 279-test Call Engine suite pass with one
tagged integration exclusion. Root
formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass. Root
tests stop at the unchanged Persistence setup failure because PostgreSQL SCRAM authentication needs
a password absent from this shell; no credential source was inspected.

A timeout-race follow-up removes synchronous cleanup from Room Authority. The red test holds the
second TTS transport inside startup until after the 750 ms restoration deadline; the prior timeout
handler then blocked while asking the busy capability supervisor to stop that partial child. The
green path schedules termination and exact source/destination cleanup as an unlinked child of the
room transfer task supervisor, clears transfer authority, archives `timed_out`, and replies without
waiting for provider startup. The task supervisor permits at most four concurrent preparation,
restoration, and cleanup tasks per room, so abandoned provider starts cannot accumulate without
bound. Releasing the transport proves it is stopped and never installed in Room Authority. The
focused ten-test transfer-room file and complete 280-test Call Engine suite pass. Root formatting,
warnings-as-errors compilation, strict Credo, and unused-dependency checks pass. Root `mix test`
stops at the unchanged Persistence setup failure because PostgreSQL SCRAM authentication needs a
password absent from this shell; no credential source was inspected.

A failed-commit race checkpoint now treats prepared participant membership as provisional until
Room Authority commits it. The red integration test suspended Room Authority after destination
preparation had completed, terminated the exact prepared participant, and then resumed commit. The
old path archived and emitted transfer completion before observing that the destination was gone.
Participant Lifecycle now verifies the prepared supervisor's exact registry ownership at commit;
an absent or replaced process returns `participant_unavailable` without adding authoritative room
state. Transfer handling discards the preparation, keeps the source active, exposes only generic
`tool_failed`, and archives the private `destination_commit_unavailable` cause. The focused
transfer/participant-supervision group passes 13 tests and the complete Call Engine suite passes
281 tests with one tagged integration exclusion. Root formatting, warnings-as-errors compilation,
strict Credo, and unused-dependency checks pass. Root `mix test` stops at the unchanged Persistence
setup failure because PostgreSQL SCRAM authentication needs a password absent from this shell; no
credential source was inspected.

The automated acceptance consolidation adds direct coverage for the remaining combined checklist
claims. Authored `transfer` aliases fail at their exact definition path; an injected schema target,
wrong source participant, stale activation, and duplicate preparation all fail before a second
destination can start. Successful commit preserves the room/incarnation, Call Variables PID, and
pinned entry refs while terminating the source participant subtree; a forged late source text event
is ignored by the new activation's authority boundary. The deadline scenario identifies the source
on its deterministic hold response and configures a fixed destination greeting, then proves that
neither that greeting nor completion appears after expired preparation is released. The pure
projection and Agent Runtime seed tests cover every history mode and reject system/tool-bearing
history. The focused transfer/compiler/history group passes 22 tests; the focused Agent Runtime seed
test passes. These checks align the older “source can converse” wording with the subsequently
approved default-blocking transfer policy. Automated acceptance is complete; rendered/manual
verification and the common completion gates remain open. The complete Call Engine suite passes
282 tests with one tagged integration exclusion. Root formatting, warnings-as-errors compilation,
strict Credo, and unused-dependency checks pass. Root `mix test` stops at the unchanged Persistence
setup failure because PostgreSQL SCRAM authentication needs a password absent from this shell; no
credential source was inspected.

The development sample now exposes the same vertical slice through the rendered console. Its
reception participant can transfer only to billing, receives a bounded trailing spoken-history
window on re-entry, and retains the existing read/write variable permissions. Billing has a fixed
first greeting, receives all confirmed spoken history, can read the synthetic order variable, and
can transfer only back to reception. The ordinary local background-report binding remains the
explicit non-blocking example; both generated transfer bindings retain the default blocking mode
while still executing in independently supervised workers.

An HTTPS browser pass reached RTVI ready at desktop and 390 x 844 viewports with fake media. The
console rendered without horizontal overflow or browser exceptions. A text turn crossed the data
channel and appeared in the conversation. The initial live transfer failed because the generated
schema represented each permitted destination with `const` inside `oneOf`, which Gemini rejects in
function declarations. The same closed allowlist now uses `enum` plus a safe descriptive label.
Both ordinary and selected-history schemas pass direct Gemini requests, and the ordinary request
returns `transfer` as expected. The rendered sample then transferred reception to billing, played
billing's fixed greeting to completion, retained the caller's spoken transfer request, and read the
permitted `order-demo-1001` variable through the blocking variables tool. A requested return to
reception produced a second transfer tool call. In the first pass, the next caller turn interrupted
the source acknowledgement's delayed audio and received no rendered response inside the bounded
window. A clean replay waited for that acknowledgement to stop before sending new input: the second
transfer committed, reception answered after re-entry, and the following caller question received
“I am the reception department. How can I help you?” in the rendered conversation. This isolates
the earlier
observation as an interruption race rather than failed re-entry.
The deterministic 282-test Call Engine suite remains green with one tagged integration exclusion.
Frontend tests and
type checking, development and test warnings-as-errors compilation, formatting, strict Credo, and
the unused-dependency check pass. A complete root test run against a disposable PostgreSQL 17
instance exposed three Persistence fixtures pinned to the superseded `20260910.05` schema. Updating
those fixtures to the current `20260910.06` schema restored the complete green umbrella suite; the
database was removed after verification.

Final milestone evidence combines that rendered happy path and re-entry with deterministic failure
coverage for unauthorized destinations, stale/wrong sources, duplicate preparation, provider
startup failure, deadline expiry, failed commit, one-shot source restoration, late-result exclusion,
history/variable privacy, and source-subtree termination. The complete database-backed umbrella
suite and all common formatting, warnings-as-errors compilation, strict Credo, and unused-dependency
gates pass. The rendered console was inspected at desktop and 390 x 844 viewports through headless
Chromium/CDP because `agent-browser` was unavailable; that substitution is recorded rather than
claiming the unavailable tool.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Specified history modes, precommit destination silence/source continuity, empty-list and total-deadline races; re-review approved.
That review was specification evidence only; the implementation and runtime evidence above now
closes the separate completion gates.
