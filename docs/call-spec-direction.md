# Call spec direction and schema compatibility

New call specs use `schema_version: "20261004.01"` and exactly one direction block.
Both blocks, neither block, and the old entry fields are rejected in this version.
Participant names are spec-local identifiers; `handled_by` must exist and differ from
the named caller or callee. A handler may be an agent or a human.

## Incoming calls

```json
{
  "schema_version": "20261004.01",
  "incoming_call": {"caller": "customer", "handled_by": "assistant"},
  "participants": {
    "customer": {
      "type": "human",
      "connection": {"service": "web", "mode": "receive", "admission": "start_call"}
    },
    "assistant": {"type": "agent", "prompt": "Help the caller."}
  }
}
```

The caller must be human with a `receive`/`start_call` connection. `service: "web"`
supports web admission. A phone connection instead names a configured telephony
service and an E.164 `number`. An agent handler defaults to `first_message.mode:
"wait_for_input"`. Existing capability selections, variables and transfers still apply.
The [development example](../examples/call-specs/development.json) includes a model selection.

## Outgoing calls

```json
{
  "schema_version": "20261004.01",
  "outgoing_call": {"callee": "customer", "handled_by": "assistant", "ring_timeout_ms": 30000},
  "participants": {
    "customer": {
      "type": "human",
      "connection": {"service": "support-phone", "mode": "dial", "number": "+15550001000"}
    },
    "assistant": {"type": "agent", "prompt": "Introduce yourself and explain why you are calling."}
  }
}
```

The callee must be human with a phone `dial` connection. Its admission is implied
`start_call`; specifying `transfer` for that participant is rejected. Other dialing
participants retain their `transfer` admission and may omit it. A callee's destination
is either an E.164 `number` or the existing protected `number_from_variable` reference.
The service owns the originating number and credentials; source cannot override them.
Save and publication use the existing service and credential checks.

The ring timeout defaults to 30,000 ms and accepts integers from 5,000 through 60,000.
It is exclusive to outgoing calls. An agent handler defaults to `generated` when its
first message is omitted; explicit `wait_for_input` and `fixed` remain supported.
Only the initial handler receives this default; other agents retain their defaults.
The runtime gates opening speech until accepted submission and the callee's media connection.

The schema and plan/storage checkpoint is implemented. The
[outgoing room runtime](outgoing-call-runtime.md) and HTTP submission endpoint pass focused
local tests. Native STS generated opening and carrier audio
acceptance remain open under the
[milestone](milestones/outgoing-calls-and-live-telephony.md). Saving or publishing an
outgoing source does not dial, and its callee creates no inbound web or phone route.

The complete [outgoing Morse example](../examples/call-specs/outgoing-morse.json) selects
Morse STT/TTS and the existing Google model provider. It emits test tones, so use it only
with an automated receiving room. Configure the `test-phone` service, bind the Google
credential, and replace its illustrative number with the other carrier's owned test number
before publication. Saving and publishing still do not submit calls. Lifecycle outcome and
timestamp fields are documented in the [API guide](operator-api-key-authoring.md#starting-an-outgoing-call).

## Historical revisions and stored plans

`20260915.01` source remains accepted with `entry_caller` and `entry_receiver`.
It is interpreted as incoming while retaining its saved source and historical entry
validation. That version rejects the new direction blocks. There is no automatic
source rewrite, and compiled plans keep the internal entry field names.

New plans carry `direction` and `ring_timeout_ms`. Their deterministic serialized
digest includes these fields. Stored plans predating them decode with incoming
direction and no ring timeout; existing stored digests are preserved. Startup accepts
both versions' supported capability selections.

## Decisions and verification

The public direction blocks replace vague entry roles while preserving historical
records and the existing internal model. A global internal-field rename was rejected
for this milestone because it would add unrelated migration work. Allowing arbitrary
`dial`/`start_call` participants was rejected: only the outgoing callee owns initial
dialing; transfer destinations retain their existing contract.

Focused tests cover validation paths, JSON/Elixir inputs, admission and opening defaults,
timeout bounds, compilation, no inbound callee routes, new/legacy save-publication,
ordinary incoming room startup and stored-plan defaults. The additive calls migration
stores nullable outgoing outcomes and request key/digest pairs, with a partial unique
index on tenant and request key. Database tests cover default/reloaded values and
same-tenant rejection versus cross-tenant reuse. Calls and HTTP tests prove request replay,
digest conflict and concurrent dial ownership. The HTTP checkpoint passed all root gates:
3,104 tests, zero failures, 98 excluded, seed 755205. D6 outcome/timestamp projection then
passed all root gates with 3,121 tests, zero failures, 98 excluded, seed 219668. Native STS
opening and carrier audio acceptance remain open.
