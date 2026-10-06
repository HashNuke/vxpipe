# Outgoing call admission

The next D5 checkpoint owns durable admission before runtime/API integration. It adds a
Calls workflow and persistence port for the currently published outgoing revision, with
no participant join credential. Existing preparation and incoming paths are unchanged.

Red evidence: six Calls tests failed because `claim_outgoing_call/5` was missing after
correcting the fixture to the supported `call_variables.sections` schema and closed object
properties. Four persistence tests failed on the missing publication lookup/claim callbacks.
The initial persistence test command was accidentally run from the root with a child-relative
path; the four intended tests ran red, but the root also reported unmatched paths for other
children. Green verification was run from the owning child as required.

Implementation: check `calls` scope before lookup; fetch the explicit publication pointer
rather than choosing the largest revision; compile/pin with the existing telephony/credential
contracts; atomically insert an admitting outgoing call with no join token. Compute SHA-256
of canonical JSON containing call-spec ID and initial variables when a key is supplied.
Replays return the existing record before rebuilding; changed requests conflict. The DB
unique constraint resolves competing inserts after rollback, while fresh authorization runs
inside the insertion transaction. An eight-request focused workflow test proves one winner;
a DB collision test proves unique-index recovery and digest conflict handling.

Focused green: Calls six tests, seed 965429; Persistence four tests, seed 279108.
Root verification and HTTP/runtime integration remain pending. No live provider calls ran.

The broader focused regressions passed after refactoring: Calls 28 tests, seed 983517;
Persistence 30 tests, seed 267038. Root format, compilation with warnings as errors,
strict Credo and unused dependency checks passed. A new full root run is in progress
(seed 303119), with no paid lanes selected. Explicitly formatted the changed/new
Elixir paths because the umbrella formatter's child globs do not reach children
without their own formatter configuration.

Next integration research (not implemented): `CallEngine.start_call` returns a room
snapshot before asynchronous preparation/dial completion. A lookup after dial is
unsafe: `OutgoingCall.finish` can destroy the room before HTTP reads it. Register a
trusted submission observer before starting the room and emit its correlated result
from the coordinator before a terminal exit. Ensure the call's durable start is
projected before dial/closure; archive closure currently requires a running call, so
asynchronous mark-started is a race. A deferred initial admission/start barrier is
one possible way to order persistence before provider submission. Any new barrier
needs focused proof of no dial before release, no second submission, failure cleanup
and initial readiness semantics. This is research, not an approved implemented gate.

Native STS research: generated first message currently returns unavailable. Reusing
`push_text` with an engine prompt can publish it as caller transcription (Morse emits
input transcript and turn end; Google emits text turn end). A generated opening
needs an explicit engine-owned operation/origin so output can use normal policy and
playback without fabricating caller input. Exact fixed native speech is also not
proven by prompting a conversational model. No speech state-machine/source-cutover
modules changed in this checkpoint.

## Accepted local checkpoint

The full root run completed with exit 0: nine applications, 3,088 tests, zero failures,
98 excluded, seed 303119. Gateway's 532 tests passed in 481.8 seconds; Persistence's
195 tests passed, including the four new DB admission tests. All other required root
gates passed. Updated milestone/index and architecture record; D5 remains unchecked
until HTTP/runtime acknowledgement is implemented and verified. No commits or paid
calls were created. Sent a pushnotify progress update.
