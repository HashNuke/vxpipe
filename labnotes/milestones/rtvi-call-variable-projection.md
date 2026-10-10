# RTVI call-variable projection

> Relocated from `docs/rtvi-call-variable-projection.md` on 2026-10-09. First recorded source commit: `42a50fbd97ce` (2026-09-16T10:20:19+07:00).
> Supporting plan/evidence companion. [call-debug-console](call-debug-console.md) owns current scope, implementation checklists and acceptance; [the index](index.md) owns order. This is not a new independently ordered milestone.
> This is the approved pending projection design. The owner retains the unchecked implementation and browser gates; relocation does not make vxpipe.variables a supported implemented extension or grant private-variable access.

Status: approved design for the call debug console; runtime implementation is pending.

## Decision

RTVI does not define call variables as a standard message. Vxpipe will project the current
authorized variable set through RTVI's standard `server-message` event, using a versioned
Vxpipe envelope alongside `vxpipe.turn` and `vxpipe.transfer`:

```json
{
  "type": "server-message",
  "data": {
    "t": "vxpipe.variables",
    "v": 1,
    "d": {
      "revision": 7,
      "sections": {
        "intake": {
          "revision": 3,
          "value": {"requested_date": "2026-09-18"}
        }
      }
    }
  }
}
```

The event carries a complete snapshot, not a patch. The server sends a baseline when an
authorized debug connection becomes ready and another snapshot after every accepted variable
update. The client replaces its local projection only when `revision` is newer. Repeated or stale
snapshots are harmless. An unknown envelope version is ignored without interrupting the call.

The connection already identifies the call and room incarnation, so those identifiers are not
duplicated in `d`. Section revisions remain available for explaining optimistic-write conflicts;
the global revision orders whole snapshots.

## Authorization and privacy

`CallVariables` owns unrestricted room state. An ordinary participant connection must never gain
that state merely because it speaks RTVI. Full snapshots are available only to a tenant-authorized
debug seat whose server-side admission grants variable inspection. The browser cannot request or
elevate this visibility.

The projection is built on the server from the authorized variable snapshot. It contains section
names, section revisions and values. It excludes schemas, grants, capability handles, credentials,
the resolved call plan and archival metadata. A participant-visible client either receives an
explicitly filtered projection or no `vxpipe.variables` event.

The Variables tab reads normalized client state rather than decoding RTVI in React. Raw RTVI
logging may observe the envelope only for the same authorized seat; it must never be written to
browser persistence, the console, URLs or an unrestricted participant stream.

## Delivery and race handling

The runtime boundary must provide an atomic subscribe-and-snapshot operation. It registers the
debug projection subscriber before reading the current state, then delivers the baseline and
subsequent revisions in order. This prevents an update between subscription and the initial read
from being lost. Slow browser delivery uses a bounded, non-blocking handoff and may coalesce queued
snapshots to the newest revision; it cannot back-pressure `CallVariables` or media work.

The existing 65,536-byte encoded snapshot limit bounds accepted variable values. Gateway encoding
still needs its own bounded failure behavior. If an authorized snapshot cannot be encoded or sent,
the client retains the last good revision and exposes the projection as stale or unavailable; it
does not display a truncated snapshot as authoritative.

Reconnect creates a new authorized subscription and receives a fresh baseline. Version 1 does not
add a browser command for resync because the server baseline is sufficient. A future request/ack
flow requires a separate versioned contract if operational evidence shows it is needed.

## UI contract

`@vxpipe/core` exposes a protocol-neutral variable snapshot with global revision, section revision
and JSON-compatible values. `@vxpipe/react` renders it read-only in a Variables tab grouped by
section. Nested values remain structured and explicit; missing and `null` values are distinct.
Editing variables is outside this milestone.

The console has three top-level views: Conversation, Variables and Metrics. Conversation is one
filterable timeline containing messages, semantic events, tool calls and optional raw RTVI logs.
The default filters enable messages, events and tool calls; raw logs are disabled. A Reset action
restores those defaults. Join, leave and transfer facts appear as concise activity rows inside the
timeline instead of a separate status bar.

Metrics use four authoritative scopes: room, room capability, participant and participant
capability. Turn-specific metrics stay attached to the corresponding message and appear from a
small metrics control beside its time. Missing attribution is omitted rather than inferred.

## Rejected alternatives

- A new top-level RTVI message type would require SDK-specific parsing for behavior already
  supported by `server-message`.
- Incremental JSON patches make reconnect, missed-event recovery and ordering more complex than
  the bounded full snapshots already owned by `CallVariables`.
- Reading the persistence projection for every live update adds lag and creates a second live
  authority. Persistence remains the durable inspection source after the call.
- Broadcasting unrestricted variables to every call participant violates the existing private
  variable and tool-projection boundary.

## Verification required for implementation

- Red-test baseline delivery, accepted updates, stale/duplicate revisions, reconnect and an update
  racing subscription.
- Prove ordinary participants receive no private snapshot and a browser cannot elevate access.
- Prove slow or disconnected clients cannot block variable updates or media work.
- Verify unknown versions and an oversized/encoding failure preserve the call and last good state.
- Exercise the Variables tab and conversation filters at 360, 768 and 1440 px in light and dark
  themes with keyboard navigation and structured/long values.
