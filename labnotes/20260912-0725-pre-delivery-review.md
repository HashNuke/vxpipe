# Pre-delivery review

## Scope

Exercise the completed pre-packaging platform as one working system after milestone 22 and before
milestones 23 (container delivery) and 24 (retention/deletion). Review the runnable Console sample,
durable admission, RTVI/WebRTC, deterministic model and speech providers, diagnostics, transfer,
recording, usage, publication, inspection, compaction and native fallback boundaries. Fix concrete
regressions in their owning milestone; do not start packaging or retention work.

The guarded live Twilio audio proof remains the already-documented external limitation for
milestone 18 because no Twilio credentials or approved destination are configured.

## Environment

- Branches: `review/pre-delivery-cross-slice` for the durable hangup checkpoint, followed by
  `review/sample-terminal-state` for the client-terminal checkpoint.
- PostgreSQL: local `vxpipe_review` database on the existing development server.
- Runtime: `VXPIPE_DEV_MODEL_FIXTURE=true`, `VXPIPE_DEV_SPEECH_PROFILE=morse`, HTTP loopback
  Console, and durable sample admission.
- Hosted speech, Twilio and S3 credentials are absent. The review must not imply those external
  integrations were re-proven live.

## Evidence and findings

### Deterministic durable sample

The rendered Console created and admitted a durable call through `POST /sample/calls` and the
participant-session route. A first cold attempt reached the RTVI offer endpoint but received HTTP
503; Pipecat retried the consumed session and received 409 responses. The UI ended at “Unable to
connect.” Diagnostics recorded one server-error RTVI offer and subsequent client-error offers.

A fresh call on the same warm BEAM connected successfully. The standard RTVI 2.1 readiness
exchange completed, typed `HELLO REVIEW` entered the room, the local model returned one assistant
row, and Morse TTS completed paced playout. Sending the text while the initial assistant audio was
still playing generated an attributed Vxpipe interruption event; the replacement response then
completed normally. Diagnostics showed one active room, no dropped observations, successful local
model first-output timing and Morse first-audio timing.

After a clean BEAM restart, a new browser and the first newly admitted call connected on the first
offer with HTTP 200. The earlier cold 503 is therefore retained as an observed transient, not yet a
reproducible contract failure and not a reason to increase timeouts speculatively.

### Operator inspection of the same sample

The trusted CLI issued a separate calls-scoped key for the newly bootstrapped sample tenant. The
secret was passed directly from command output into the browser form without being printed or
stored. The real operator session then showed the same running sample call with:

- matching live and persisted event revisions and participant/room/incarnation identity;
- locally measured Morse character and playout-duration observations attributed to the exact
  participant, activation and turn;
- explicit “No revisions” while the call remained live and publication had not begun;
- explicit “No artifacts” because recording/object storage was not configured; and
- bounded live and persisted event ledgers with no fabricated timing values.

Opening a call public ID belonging to an older sample tenant returned “Call not found” and no call
data. At a 390×844 viewport the detail page had equal client and document widths (no horizontal
overflow). The WCAG A/AA browser audit reported zero violations; two usage-table cells were
inconclusive because the automated checker could not determine the background beneath them.

This review exposed an integration usability gap: the development definition does not grant its
agents the already-implemented platform `hangup` tool. A sample call therefore cannot exercise its
normal terminal event, call-details publication or post-call inspection without waiting for the
30-minute duration limit or using engine internals. The opening/lifecycle milestone's runnable
outcome explicitly includes an agent using the hangup tool. Add it to the development agents and
instructions through a focused configuration contract, then use the real model plus Morse TTS to
end a browser call.

The development definition now grants both sample agents the platform `hangup` tool and instructs
them to invoke it when the caller asks to end the call. The focused Console configuration contract
failed first because both bindings were absent, then passed after the configuration change.

A real Gemini-backed browser call subsequently invoked `hangup`: the tool start/completion reached
the UI and the room/media tree stopped, but the durable call remained `running` after the archive's
five-second drain deadline. PostgreSQL contained every fact through `tool_call_completed` and no
`archive_stream_closed` fact.

The engine-only hangup boundary did emit and drain its closure normally. A new persistence-owned
integration test then reproduced the full failure: EctoStorage repeatedly attempted the closure
until the bounded subscriber expired, leaving the call running. The terminal projection passed a
millisecond-precision archive timestamp directly into an `:utc_datetime_usec` field; Ecto raised
before the transaction could commit. Normalizing that timestamp to six-digit microsecond precision
inside the persistence projection makes the same engine-to-Ecto hangup flow store the closure and
atomically mark the call ended.

The complete Persistence suite passed with 48 tests and the complete Call Engine suite passed with
405 tests plus one explicitly excluded integration case. The repeat rendered-browser call used the
real Gemini model and local Morse speech profile. Asking it to end the call produced the visible
`hangup` function call, stopped the live room/media tree, persisted `archive_stream_closed` as fact
sequence 14, and changed the same call row to `ended` at the archive stop timestamp. This confirms
the ordinary durable terminal path rather than only the isolated timestamp conversion.

The first root-suite verification run also exposed a pre-existing monitor race in the
`PublicationFinalizer` test. A finalizer can send its explicit skipped notification and finish
normally between `start_child/2` returning and the test installing its monitor; OTP then reports the
corresponding `:DOWN` reason as `:noproc`. The focused assertion now accepts either `:normal` or
`:noproc` only after observing the explicit skipped event. Its focused test passes, and the change
was committed separately from the hangup behavior correction.

After that test-harness correction, the complete root suite passed with 989 tests and zero failures;
15 external-network integration cases remained explicitly excluded. The root formatting check,
warnings-as-errors compilation, unused-dependency check and strict Credo analysis also passed.

The live pass exposed a separate client-lifecycle issue: after server hangup, the Small WebRTC
client attempted its configured reconnections with the already-consumed session, correctly
received HTTP 409 from the server, and exhausted the attempts, but the sample still rendered its
Disconnect control and did not log a final disconnected transport state. Preserve the decision
that a disconnected caller does not silently resume an ended call; investigate why the sample does
not project the exhausted transport state before changing protocol or token semantics.

Inspection of the installed client transport found that retry exhaustion calls its transport stop
path directly. That path emits its disconnect callback but does not itself advance the transport
state shown by the Console. The transport's graceful remote-terminal path instead expects a Small
WebRTC `signalling` message whose nested type is `peerLeft`; its default bot-disconnect behavior then
performs the full client disconnect transition. This is an ended-call notification, not a new
reconnection mechanism or permission to reuse the single-use session.

A new real ExWebRTC boundary test established a client, ended the monitored room, and initially
failed after five seconds because the connection closed without delivering `peerLeft`. Sending the
signal and immediately stopping remained red: SCTP teardown overtook observable delivery. Gateway
now encodes the transport signal in a dedicated signalling module, sends it when the monitored room
exits, and allows at most 250 milliseconds for peer-initiated disconnect before stopping the
connection itself. If no RTVI channel exists or the send process is unavailable, it closes
immediately. The focused test now receives the exact signal before the connection's monitored
`:shutdown`; the complete WebRTC boundary file passes three tests.

The sample UI test first proved the stale-state behavior by failing to find its Create room action
after the client's disconnect callback. The Console now treats that callback as terminal for the
consumed admission, unmounts the old console, and returns to the dedicated creation page; all six
App tests and all nine frontend tests pass with TypeScript checks green.

The rendered browser verification used a durable call, the real Gemini model, and local Morse
speech. Asking the agent to end the call produced the expected platform tool lifecycle, delivered
`peerLeft`, logged the client's bot-disconnect transition, and returned to Create room without a
reconnect attempt or HTTP 409. The desktop and 390-by-844 mobile terminal views matched the existing
surface, had no horizontal overflow, and produced no browser errors. The WCAG A/AA audit reported
zero violations and zero incomplete checks.

The owning verification lanes pass with Gateway at 228 tests and six excluded integrations,
Console at 89 tests, frontend assets at nine tests, and TypeScript checking clean. Formatting,
warnings-as-errors compilation, unused-dependency checking, and strict Credo all pass. The first
umbrella run reported one Gateway failure whose detail was lost when the verbose media output was
truncated; the same Gateway seed passed immediately, the complete umbrella rerun passed all 990
tests with 15 external integrations excluded, and the new signal-ordering test passed 20 consecutive
in-VM repetitions. No deterministic failure was reproduced, so no unrelated timing change was made.

### Durable/runtime lifecycle observation

The review database contains multiple rows still marked `running` although their earlier BEAM room
trees no longer exist. This is expected to arise when the development VM stops without a terminal
room event, but the final desired state is not yet assumed. Investigate the approved crash semantics
and existing reconciliation contracts before changing it; this is separate from retention/deletion.

### Next isolation step

Restart the BEAM, capture the first offer response and narrowly inspect connection/pipeline startup
timing. Decide from evidence whether the cold 503 is a request timeout, pipeline-start failure or a
different lifecycle race. Reproduce under a focused project-owned test before implementation.

That restart did not reproduce the 503. The durable sample hangup and client-terminal corrections
are verified. The next review checkpoint is the stale durable/runtime lifecycle observation above;
it must be evaluated against approved crash semantics without starting retention or deletion work.
