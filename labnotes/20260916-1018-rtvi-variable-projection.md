# RTVI variable projection

## Goal

Plan how the debug console receives and displays live call variables without inventing a
nonstandard RTVI message or weakening the private variable boundary.

## Findings

- The RTVI standard has no call-variable event. Its standard `server-message` event accepts
  arbitrary JSON-serializable server data for custom interactions.
- Gateway already uses versioned `server-message` envelopes for `vxpipe.turn` and
  `vxpipe.transfer`, so `vxpipe.variables` fits the existing extension convention.
- `CallVariables` owns full sectioned snapshots with a global revision, per-section revisions and
  a 65,536-byte encoded snapshot limit. Baseline and update snapshots already flow to private
  archive/inspection ports.
- Existing participant/tool visibility rules explicitly prevent unrestricted private snapshots
  from reaching ordinary clients. A generic broadcast to every RTVI seat would violate that
  contract.

## Decision

Use an authorized `vxpipe.variables` version 1 `server-message` carrying the complete current
snapshot. Send a race-free baseline when a debug seat becomes ready and a newer snapshot after
each accepted update. Core rejects stale revisions; React receives normalized state. Admission
chooses visibility server-side and browsers cannot elevate it.

Keep the console views as Conversation, Variables and Metrics. Conversation includes filtered
messages, semantic events, tool calls and raw RTVI logs. Metrics use room, room-capability,
participant and participant-capability scopes; turn metrics remain attached to messages.

## Rejected approaches

- A custom top-level RTVI type duplicates the generic extension mechanism.
- Patches complicate reconnect and missed-event recovery.
- Reading persistence as the live source creates lag and a second authority.
- Broadcasting the full snapshot to all participants leaks private values.

## Evidence

- Source inspection: `Vxpipe.CallEngine.CallVariables` snapshot/revision/size contracts and
  `Vxpipe.Gateway.RTVI.Codec` extension envelopes.
- Protocol reference: <https://docs.pipecat.ai/client/rtvi-standard> (`server-message`).
- Durable design: `docs/rtvi-call-variable-projection.md`.
- Documentation-only checkpoint; Markdown links and diffs were inspected. Runtime and browser
  acceptance remain pending in the call-debug-console milestone.
