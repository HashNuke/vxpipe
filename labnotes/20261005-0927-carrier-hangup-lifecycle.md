# Carrier hangup lifecycle

The previous live Twilio-to-Telnyx call passed reciprocal markers and outgoing-room shutdown,
but the receiving room missed its ten-second shutdown bound (seed 201787). Current production
incoming admission handles media_started/media and rejects terminal events. Both initial
answering and running incoming legs need to deliver a verified terminal event to their own
room, including a hangup before media starts. No further paid call is needed to reproduce
this project-owned boundary locally.

The checkpoint uses an Engine-owned trusted termination operation scoped to tenant, room and
exact incarnation, validated atomically in RoomAuthority. Gateway forwards only its already
authenticated and correlated incoming leg termination. The ordinary supervision/archive
shutdown path remains responsible for closure. Stale and cross-tenant identities cannot stop
a current room. Avoid passing a raw Registry PID or spoofing agent tool authority from Gateway.

Started the smallest Engine test: wrong tenant and stale incarnation leave the monitored room
intact; the correct incarnation ends while startup/media are still preparing; a repeat reports
unavailable. The API is missing, so its first run must fail before implementation. An additional
Gateway signed terminal-event regression and full archive acceptance will follow this boundary.
No credentials, provider resources or dialing permissions have changed.

The initial line selector targeted an attribute rather than the new test and ran zero tests;
it is not red evidence. Corrected selection ran one test and failed on missing end_call/3
(seed 380525). Implemented the bounded public API, supervisor lookup and atomic incarnation
comparison/normal stop in RoomAuthority. The full lifecycle file passes 19 tests/zero failures
(seed 761273). No source-cutover or speech-state transitions changed.

Added signed Telnyx terminal regressions before media and after authenticated media startup,
including an unrelated leg that must leave the monitored room intact. Both failed with HTTP
503 before implementation (seed 685383). Incoming Leg now forwards matching ended events in
answering/running phases; the production backend ends the exact activation incarnation.
Unavailable old incarnations are terminal acknowledgements. The leg enters ended phase,
handles an immediate repeated terminal event without another backend operation, and retires
on room DOWN without redundantly hanging up an already ended carrier leg. Both new Telnyx
cases pass (seed 861874).

Twilio's incoming number has no additional terminal callback provisioned, and its media
decoder ignored matching stop frames. The existing `<Connect><Stream>` is bidirectional;
official Twilio WebSocket and TwiML docs say stopping that stream requires ending the call.
Added a decoder test requiring a terminal Event with strict account/call/stream matching,
and an authenticated WebSocket harness test requiring room/leg DOWN and no redundant REST
hangup. The harness failed on missing room DOWN (seed 899941); the decoder failed with :ignore
(six tests/one failure, seed 597190). Implemented stop normalization through the existing
Event dispatch, preserving all identity checks and observation time. It does not infer
hangup from a generic socket disconnect, nor change Telnyx stream-stop semantics. Started
the complete two-harness/decoder/ingress group before another paid attempt.

The complete Gateway group passes 43 tests/zero failures (seed 939576), including both signed
Telnyx phases, Twilio authenticated stop, strict mismatched-stop identity rejection, existing
transfer/recovery behavior and carrier usage ingress. Format, warnings-as-errors compilation
and unused-dependency checks pass. Strict Credo rejected RoomAuthority reaching 803 lines;
after the focused tests were green, tried equivalent exact-incarnation pattern-matching
clauses. Formatting expanded that head and the file reached 805 lines, so this did not fix
the check. Moved the termination policy into the existing cohesive RoomAuthority.EndCall
module, leaving one delegated authority callback. No check is suppressed and no semantic
change is intended. Its focused and strict rechecks are pending. Lean builds/oracle/replay
pass (one replay test).
Started a full same-seed umbrella recheck after these production changes.

Started an explicitly selected live sequence: public health on all three IPv4 relays for
three consecutive probes, free signed endpoint admission, then at most one Twilio, Telnyx
and unanswered case each, stopping after any failure. Its temporary parent always stops
the node, holds it online between cases and writes diagnostics to a mode-0600 local log.
No credentials pass through argv; no credential file is read by the helper. Carrier calls
still run only through bin/livetests's existing child loader, with no automatic redial.

All required selected live cases are terminal and green in one parent run: public signed
admission seed 784537; Twilio-to-Telnyx seed 106192; Telnyx-to-Twilio seed 662627; unanswered
Twilio-to-Telnyx seed 247633. Each selected case passed one test, eight excluded. Both answered
cases assert opposing human marker transcripts, outgoing and incoming room DOWN and both
durable archive closures, with answered submission/answer/end timestamps. The unanswered
case reports no_answer, no answer timestamp, one submission and the five-second ring bound
plus its existing margin. The parent stopped the node; tools:status reports running no.
No more paid calls are required for this milestone.

Strict Credo passes after moving the incoming termination policy into the existing EndCall
module. The combined lifecycle/platform-tool focus (seed 158150) passed the new lifecycle
cases but the existing agent-tool test missed ToolCallStarted under its default 100 ms
assert_receive while the full umbrella was running. The agent authorization function is
unchanged. Started the exact same focused group and seed to distinguish the observation
budget from a persistent agent-hangup failure; no runtime fix or test repair is claimed yet.

The exact focused lifecycle/platform-tools group and seed pass on recheck: 20 tests/zero
failures, seed 158150. No timeout or authorization code was changed for that observation.
The live root process also passes all 1,882 Engine tests. The single 100 ms focus miss remains
recorded as transient timing evidence rather than a repaired runtime bug. Strict Credo is
green with EndCall owning the new scope policy and RoomAuthority delegating the callback.
Started the three existing shell suites to audit runner isolation, tooling lifecycle and
fake-carrier provisioning contracts on the final worktree. These use their own synthetic
credential files and fake tools, never the real live credential file or external accounts.

All three shell suites pass (runner, tools, provisioning), including no-purchase refusal,
idempotent repeat, foreign-resource preservation, read-only preflight, isolated child env,
owned-node cleanup and override/lock behavior. The full Engine suite passes 1,882 tests;
Gateway remains live under its original root process handle. The milestone E and harness
evidence now record all three successful live gates and the incoming repair, while the
milestone index remains unchecked until the final umbrella gate passes. Public Funnel
stabilization and the distinction between first-opening semantics and reciprocal marker
audio remain explicit limitations, not hidden by widening the paid assertions.

Final root process is terminal and green: 3,156 tests/zero failures/103 excluded across all
nine applications, seed 930118 (`vxpipe-carrier-end-root.log`). Engine passes 1,882, Gateway
549, Console 200; all project-owned failures in that run are resolved. The root gate covers
the incoming repair, and the semantically equivalent EndCall policy extraction additionally
passes its 20 focused lifecycle/platform-tool cases. Formatting, warnings-as-errors compile,
strict Credo, unused dependencies, three shell suites and Lean are green. The full completion
audit checked A–E and the milestone's five acceptance/failure checks against implementation,
these test results, the four selected live case results, prior real provisioning/no-purchase
evidence and current stopped-node status. No required carrier call or implementation remains.
E and the milestone index are checked; the index now has 29 complete and 10 incomplete
milestones. The separate original Twilio legacy live lane is not claimed to have been run.
No commits, extra paid calls or additional account changes were made for this checkpoint.

The final current Tailscale client ID/secret pair also passes a fresh OAuth token exchange
through the existing runner child loader. The returned token was discarded in memory;
only the accepted boolean was printed. This selected child override ran no actual Deepgram
test and started no Funnel. The temporary helper was deleted. This gives current paired
OAuth evidence alongside the actual carrier REST/signature evidence in both live directions.
Final documentation verification checks 168 local links/fences without issues and confirms
zero unchecked tasks in the completed milestone. The test node remains stopped.
