# Room policy failure ownership

## Decision

RoomAuthority monitors the planned room's media-policy authority and owns the resulting room
closure. The policy authority remains temporary and is never restarted within a live room.
It stops immediately on a required enforcer failure; it cannot accept a later policy change.
RoomAuthority records an outstanding transfer's failed progress and bounded archive fact before
returning its stop result. Its significant-child exit then tears down the incarnation and all
owned media, participants and transfer workers.

This serializes two previously competing actions: recording a failed transfer and shutting down
its coordinator. A destination recognizer can fail after adoption while release is still pending.
Previously the policy authority's significant-child exit could terminate RoomAuthority before it
processed the recognizer's unavailable message. The call closed, but its required failed progress
and transfer history were missing.

## Alternatives and implications

- Keeping both shutdown owners and publishing earlier still races the supervisor's termination.
- Delaying policy failure with a timer changes failure timing and does not establish ordering.
- Emitting required history from `terminate/2` makes correctness depend on best-effort cleanup.
- Removing the failure assertions would weaken the approved partial-release contract.

The room's mixer and transcript router retain their existing significant-child supervision.
A policy crash still closes an ordinary room; pending transfers gain terminal failure handling.
A policy exit during the coordinator's synchronous commit request is returned as a bounded
commit failure, so that path also records failure before stopping. A rejected privacy barrier
records the same terminal commit-failure fact. Handling policy loss closes the room without
starting source recovery or completing destination activation.
The coordinator's ordinary bounded mailbox work precedes handling its policy monitor; this does
not introduce another retry, timeout extension, reconnect path or synchronous policy callback.

## Verification

A deterministic Engine case suspends RoomAuthority during a partially acknowledged handoff,
disconnects the destination's actual test speech transport, awaits the policy process's enforcer
failure and then resumes RoomAuthority. It requires failed progress, the specific speech failure
history fact, room shutdown and no recovery/activation. A separate case kills the policy authority
directly during release. Barrier cases cover both rejection and policy death while the real
commit call is pending, with failed progress/history and no bridge. Existing planned-room
acceptance checks closure after policy loss outside a transfer. Results are recorded in the [checkpoint labnotes](../labnotes/20260915-2122-handoff-speech-failure.md).
