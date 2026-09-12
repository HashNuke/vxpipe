# Usage and billing observations

## 2026-09-11: first checkpoint scope

Milestone 20 starts with a provider-neutral typed observation and settlement boundary in Call
Engine. The existing agent runtime already preserves bounded raw model usage and provider metadata,
but Call Engine does not yet translate its usage event. Hosted speech, tools, and carrier adapters
also do not share one typed contract.

The first red test specifies separate value objects for attribution, provider context, one measured
component, one call-scoped observation, and derived effective amounts. A settlement groups by
provider attempt, component, unit/currency, provenance, and honest attribution. It deduplicates only
a repeated delivery identity; equal independent deltas remain distinct. Cumulative ordering uses
source sequence, while final and correction status are independent from delta/cumulative mode.
Included subcategories remain inspectable without being added to their declared aggregate.

The focused test first ran with five failures because none of the typed usage modules existed. This
was the expected red state; the failures occurred at the new public constructors rather than in
unrelated runtime setup.

## 2026-09-11: typed contract green

Call Engine now owns small typed values for attribution, provider context, measurement,
observation, and effective amount. The public settlement module delegates replay detection,
amount derivation, and component-inclusion validation to separate modules so those policies have
independent reasons to change. The largest implementation module in this checkpoint is the
focused amount reducer rather than a combined validation/aggregation/logging module.

Counts use non-negative integers in canonical token, character, millisecond, or request units.
Money uses a currency tuple and an exact `Decimal` parsed from a plain decimal string; floats are
rejected. The owning application now declares `decimal` directly instead of relying on a
transitive dependency. Totals do not cross provenance unless the caller selects a provenance.
This keeps a library estimate from being silently added to provider-reported cost.

Replay detection needed a second red/green pass. A delivery can be proven by stable observation
ID, transport delivery ID, or source sequence, so the implementation checks all three rather than
choosing just one. Equal values with no shared identity still add. Reusing an identity for
different semantic content is rejected as conflicting evidence.

Verification so far:

- Focused red: five missing-contract failures, followed by two deliberate replay/provenance
  failures after expanding the contract.
- Focused green: 6 tests, 0 failures.
- Call Engine: 363 tests, 0 failures, 1 existing integration exclusion.
- Strict Credo: 671 source files, no issues.
- Umbrella: formatting, warnings-as-errors compilation, all 851 tests across eight apps, and the
  unused-dependency check pass.

No adapter capture, persistence, operator projection, or billing lookup has been implemented yet.

## 2026-09-11: completed model-round capture

The next red/green pass exposed four separate boundaries rather than putting translation,
correlation, authorization, and serialization into the coordinator or room process:

- `ModelProjection` accepts only non-negative integer input/output/total token evidence and safe
  provider identity. Arbitrary metadata and ambiguous floating-point cost fields do not cross the
  boundary.
- `UsageRounds` tracks each Agent Runtime request until its terminal event. This is intentionally
  separate from the coordinator's current task because usage and task-result messages have
  different senders and may reach the mailbox in either order.
- `UsageObservations` authenticates the emitting capability and pinned identities before changing
  the room's archive recorder.
- `ArchiveProjection` produces explicit JSON-safe private facts rather than relying on generic
  struct serialization.

An observation can now omit its measurement. This retains genuine request/session identity when a
provider returns no supported usage or price, and settlement then has no effective amount for that
operation. It reports the unit as unknown rather than inventing zero.

Each successful model response creates one distinct attempt per model round, including intermediate
tool rounds. Input and output tokens are marked as included in total tokens only when total tokens
were actually supplied. Provider request/response/session IDs remain private; local attempt IDs are
never substituted for them. The room accepts the active agent capability and a source capability
awaiting teardown after a committed transfer so incurred usage is not lost solely because authority
has moved.

Red evidence:

- The measurement-less operation was rejected as `:invalid_observation`.
- The projector calls failed because no projector module existed.
- The first coordinator usage test failed startup because call/provider usage identity was not part
  of its configuration.
- The full-room test hit the missing `RoomAuthority.handle_info/2` clause and then timed out waiting
  for a private usage fact.

Focused green evidence so far:

- Settlement and projector: 9 tests, 0 failures.
- Coordinator: 20 tests, 0 failures, including two model rounds around an asynchronous tool.
- Definition-driven private archive case: 1 test, 0 failures.
- Activation supervisor: 5 tests, 0 failures.
- Formatting, warnings-as-errors compilation, and strict Credo over 676 source files pass.

The first complete Call Engine run found four direct activation-supervisor test fixtures that
bypassed call-plan startup and therefore lacked the new explicit call/provider usage identity.
Those fixtures now provide the same internal contract and their focused tests pass. The complete
Call Engine suite passes 369 tests with one existing integration exclusion. All 857 tests across
the eight umbrella apps pass, as do the formatting, warnings-as-errors compilation, strict Credo,
and unused-dependency gates. Failed/interrupted model attempt capture, hosted speech, tools,
carriers, operator totals, and billing lookup remain.

## 2026-09-11: failed and cancelled model attempts

The successful-response path alone could not prove that a failed or cancelled request had reached
the provider. Recording every request start would be dishonest because pending invocation or model
context lookup can fail before a provider is called. Agent Runtime now emits a
`model_attempt_started` event immediately before provider generation, after those prerequisites
succeed. Every valid provider response emits its completion metadata, even when both bounded maps
are empty.

`UsageRounds` now opens an attempt on the start event and closes it on response usage. A terminal
failure or cancellation closes any still-open attempt as a measurement-free observation. This
retains the known provider operation without manufacturing token or price values. A setup failure
with no start event produces no operation. Attempt IDs are generated per actual start, so a retry
that reuses a command/correlation cannot collide with the interrupted attempt.

The round tracker remains independent of the coordinator's current text task. Consequently, usage
that Agent Runtime has already handed off remains recordable even if stale conversational output is
subsequently suppressed. Cancellation may prevent the provider from returning final measurements;
the operation still remains visible with a `cancelled` outcome and unknown measurement.

The stream-budget path needed a separate red/green pass. A provider can return a valid final
response with usage even after the local output byte/event budget rejects its text. Agent Runtime
now emits that known usage before returning the local failure, while continuing to suppress the
rejected text.

Red evidence:

- Both Agent Runtime usage tests timed out waiting for the absent attempt-start event.
- The coordinator failure and cancellation tests timed out waiting for their absent private usage
  observations while the existing capability failure events were present.
- The streaming-budget test timed out waiting for the usage attached to a valid but locally rejected
  provider response.

Green evidence so far:

- Agent Runtime usage boundary: 2 tests, 0 failures.
- Agent Runtime streaming-budget case: 1 test, 0 failures.
- Coordinator: 22 tests, 0 failures.
- Complete Agent Runtime suite: 59 tests, 0 failures, 2 integration exclusions.
- Complete Call Engine suite: 371 tests, 0 failures, 1 integration exclusion.
- Root gates: formatting, warnings-as-errors compilation, strict Credo over 676 source files, all
  860 tests across eight apps, and the unused-dependency check pass.

Hosted speech, tool and carrier capture, persisted settlement/operator totals, and billing lookup
remain.

## 2026-09-11: text-to-speech attempt capture

The next adapter checkpoint records synthesis work at the boundary where evidence becomes real.
An attempt begins only after the transport accepts `Speak`; a queued request or locally rejected
`Speak` produces no observation. If `Speak` succeeds but `Flush` fails, the input has crossed the
owned transport boundary, so the attempt is retained as failed without inventing provider IDs or
generated-audio duration.

The pinned synthesis runtime now carries call, participant activation, configured profile, and a
provider-owned safe identity. The hosted adapter reports its stable provider/model identity and the
deterministic tone adapter reports its provider identity. Credentials remain inside the existing
provider and transport values and are not copied to usage. The older room-command path lacks the
same pinned call/profile evidence and remains unobserved rather than receiving guessed values.

`TextToSpeechAttempt` owns one attempt's provider identifiers and measurements. It counts input as
Unicode graphemes and decoded provider output as PCM frames. Generated duration uses
`Membrane.RawAudio.bytes_to_time/2` and `Membrane.Time.millisecond/0`; it is not inferred from
playout progress. This matters during interruption: decoded audio that is deliberately discarded
still represents generated provider work, while a sink's played milliseconds describe a different
fact. Successful completion settles before playout drains, so a later sink failure cannot rewrite
or duplicate the provider outcome.

The large synthesis GenServer only marks lifecycle boundaries. A small child adapter creates,
updates, and finishes optional usage state, while the attempt module owns projection. Room usage
source resolution is also separate from archive recording and now recognizes the exact active TTS
process and the exact prepared private-briefing TTS process. Participant and optional activation
must still match the observation before the ordinary private archive accepts it. No raw synthesis
text or client event is added.

Red evidence:

- Three attempt tests failed because the attempt module did not exist.
- Success, interruption, and provider-error capability tests timed out waiting for usage events.
- Definition-driven tests found neither pinned synthesis usage identity nor private archived facts.
- Controlled transport tests returned `:ok` until the fixture could reject `Speak` or `Flush` at
  the requested boundary.

Green evidence:

- Attempt projection: 3 tests, 0 failures.
- Synthesis capability: 9 tests, 0 failures.
- Focused runtime, definition-driven archive, and private-briefing archive paths pass.
- Complete Call Engine: 377 tests, 0 failures, 1 integration exclusion.
- Root formatting, warnings-as-errors compilation, strict Credo over 679 source files, all 866 tests
  across eight umbrella apps, and unused-dependency checks pass.

Speech-to-text, tool and carrier observations, persisted settlement/operator totals, and billing
lookup remain.

## 2026-09-11: speech-to-text session capture

The recognition boundary differs from synthesis because one provider transport can cover several
final turns. The implementation therefore uses one local attempt plus one service-interval identity
per concrete transport and emits per-final-turn deltas within that attempt. A replacement transport
after a media-policy revision receives new identities rather than extending the previous interval.

The hosted provider's normalized final-turn signal now carries the validated audio-window duration
as integer milliseconds. Only the final turn produces provider-reported recognized-audio duration;
interim, eager, resumed, and repeated final turn state produces no duration or character delta. A
final transcript is counted in Unicode graphemes only when the interval's media policy permits
transcript storage. The tracker stores no transcript content, and a provider without final-window
evidence leaves duration absent.

An accepted audio submission or normalized provider activity proves that an attempt exists. The
first such evidence creates a measurement-free in-progress boundary. A connection-only boundary is
buffered until later bound activity or terminal publication because the provider transport can
connect before the room has bound the capability to its participant connection. Policy replacement
closes the old interval as cancelled; provider or transport failure closes it as failed. Accepted
audio followed by failure is retained even when no provider request ID or measurement arrives.

The implementation was split after its first green pass. `SpeechToTextSession` owns evidence,
interval lifecycle, and final-turn deduplication. `SpeechToTextProjection` owns typed measurements
and immutable observation construction. The capability adapter owns optional state integration and
policy-based character permission. The room source resolver separately authorizes only the exact
recognition process bound to the participant connection.

Red evidence:

- Provider tests failed on the absent normalized audio-duration field and safe usage identity.
- Pure session tests failed while the session projector did not exist.
- Capability tests timed out waiting for final measurements, cancelled replacement intervals,
  denied-transcript behavior, and failed terminal observations.
- A transport-accepted audio/no-provider-response case timed out until accepted submission became
  attempt evidence.
- Interval-boundary assertions failed until start and terminal observations were explicit.

Green evidence so far:

- Pure session lifecycle/projection: 3 tests, 0 failures.
- Recognition capability: 7 tests, 0 failures.
- Hosted provider adapter: 6 tests, 0 failures.
- Pinned runtime and definition-driven private archive cases pass.
- Complete Call Engine: 385 tests, 0 failures, 1 existing integration exclusion.
- Root gates: formatting, warnings-as-errors compilation, strict Credo over 682 source files, all
  874 tests across eight apps, and the unused-dependency check pass.

Tool and carrier observations, persisted settlement/operator totals, and billing lookup remain.

## 2026-09-12: tool-invocation capture

The next boundary is the activation-owned supervised invocation registry, not an arbitrary tool
implementation or result payload. Once the registry has successfully started a worker, it creates
one local `tlatt_` attempt and records one locally measured `invocations` request. Reconciliation
of a duplicate identity/fingerprint returns the existing acceptance without duplicating this
measurement.

The registry records a separate terminal observation for the worker's real succeeded, failed, or
unknown outcome. Its bounded timeout therefore stays unknown. Conversation interruption does not
cancel the independent worker under the approved behavior, so no cancelled usage is fabricated;
the later worker outcome remains authoritative.

Provider mapping is isolated from attempt projection. Host actions use `host_application`;
engine-owned platform, transfer, and Call Variables tools use `vxpipe`; remote tools use
`remote_mcp` with the pinned configured integration ID. Remote result metadata is not a standard
billing envelope, so it is ignored for usage and no provider operation/request/session ID is
invented. Tool arguments and results continue through existing private history and never enter the
usage structs or facts.

`InvocationUsage` owns optional configuration and private publication. `ToolAttempt` owns the safe
attempt state and observations. `ToolProvider` owns binding-to-namespace mapping. The already-large
registry gained only lifecycle delegation and an optional attempt on its existing invocation
record. Room authority reuses exact current/committed-teardown agent source authorization before
archival.

Red evidence:

- `mix test test/vxpipe/call_engine/usage/tool_attempt_test.exs --max-cases 1` first failed with an
  undefined `ToolAttempt.start/4`.
- Terminal and remote namespace cases next failed because the terminal API and safe integration
  field did not exist.
- The registry case failed startup with `:invalid_configuration` before its usage contract was
  accepted.
- The definition-driven archive assertion identified that `get_current_time` in that fixture is a
  host-provided action, so its namespace was corrected from `vxpipe` to `host_application`.

Green evidence so far:

- Pure tool attempts: 3 tests, 0 failures.
- Registry lifecycle: 5 tests, 0 failures, including duplicate suppression and timeout-as-unknown.
- Relevant descriptor, activation-supervisor, conversation, and definition-driven archive cases
  pass in a 22-test focused run.
- Complete Call Engine: 390 tests, 0 failures, 1 existing integration exclusion.
- Root gates: formatting, warnings-as-errors compilation, strict Credo over 685 source files, all
  879 tests across eight apps, and the unused-dependency check pass.

## 2026-09-12: carrier-leg capture

Carrier accounting now begins at the common answer/dial adapter boundary. Local validation and
media admission happen first, so a request that never reaches the adapter does not create a carrier
attempt. Once the adapter is about to run, one locally measured `carrier_legs` request is emitted.
The internal telephony-leg ID remains the local attempt and attribution ID; it is not copied into an
external provider identifier.

Accepted submission or event evidence retains the actual external leg as the operation ID and the
external session when supplied. Answered or media-started evidence sets the first connected
boundary. An ended event produces `connection_duration` only when the end does not precede that
boundary. Explicit event-time provenance prevents a locally observed receipt time from being
reported as provider supplied. Later provider timing can improve an earlier local media-start
boundary without adding a second connected fact.

Adapter rejection produces a failed terminal observation with no duration. Local cancellation and
ambiguous submission cleanup use cancelled or unknown outcomes without treating the end-command
request as proof that the carrier leg ended. Replayed connection or terminal evidence has no second
effect. A test exposed that the first wiring observed an ended event before binding validation; the
ordering was corrected so mismatched events cannot settle usage.

Responsibilities remain split: the Call Engine attempt module owns lifecycle state and timing
boundaries while its projection module builds immutable observations. The Gateway leg-usage adapter
owns state/reporting coordination, a separate module translates provider-neutral event evidence,
and the reporting port isolates reporter failure. Incoming/outgoing leg owners retain only the
current optional usage state. The default reporter sends scoped observations to the live room's
existing private archive path without SQL or a client event.

Red evidence:

- Five pure attempt scenarios began with the module absent, then exposed unavailable-duration and
  later-provider-evidence gaps during iteration.
- Outgoing and incoming lifecycle cases initially timed out waiting for carrier observations.
- The controlled rejected dial initially returned success.
- A mismatched ended event initially emitted a false terminal duration.

Focused green evidence so far:

- Pure carrier attempt projection: 5 tests, 0 failures.
- Private live-room carrier archival: 1 test, 0 failures.
- Outgoing leg lifecycle: 13 tests, 0 failures.
- Incoming leg lifecycle: 6 tests, 0 failures.
- Incoming activation: 3 tests, 0 failures.
- Carrier webhook decoder focus: 31 tests across the selected lifecycle/decoder files, 0 failures.
- Complete Gateway: 227 tests, 0 failures, 6 existing integration exclusions.
- Root formatting, warnings-as-errors compilation, strict Credo over 691 source files, all 888 tests
  across eight apps, and the unused-dependency check pass.

Persisted effective projections/operator totals and billing enrichment remain.
