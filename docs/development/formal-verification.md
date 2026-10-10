# Formal verification of speech-to-speech state changes (Lean)

Status: slice 1 in progress. This document is a decision record, not an
acceptance claim. The Lean toolchain and the `verification/` project are
developer tooling; `mix test` does not require Lean.

## Decision

Model the project-owned state machines that gate speech-to-speech source
cutover in Lean 4, one vertical slice at a time. Each slice ships:

1. a Lean model of the machine's states and transitions,
2. machine-checked invariants for the safety property that slice owns, and
3. a **conformance oracle**: a small, checked-in table of the model's transitions
   or admission decisions, replayed by a tagged Elixir test against the actual
   implementation module.

The Elixir code stays the implementation. Lean is a specification oracle, not a
replacement or an extractor. The oracle catches drift between the proof and the
code; the proof catches reasoning gaps the oracle's finite enumeration would
miss.

We deliberately avoid mathlib. The slice machines are finite or
counter-based, and core Lean plus `Std` (`decide`, `simp`, `omega`, `cases`) is
enough. This keeps the toolchain small (the workspace disk is tight).

## Why not one full model up front

The room/participant/capability lifecycle is large and still changing. A single
waterfall model would lag the code and deliver no usable proof until the end.
Vertical slices give a runnable, checked artifact every checkpoint and let the
model grow with the implementation.

## Slices

- **Slice 1 — SourceGate admission.** The three-state telephony media gate
  (`nil` / `held` / `active epoch`). Prove: a hold admits no epoch; an arm
  admits exactly its epoch and nothing else; re-holding keeps the epoch but
  closes admission. Ship an admission/transition table replayed against
  `Vxpipe.Gateway.Telephony.SourceGate`.
- **Slice 2 — SourceEpoch composition.** Add the socket-side hold/arm with
  fresh held epochs and token matching, downstream of slice 1. Prove: a frame
  stamped before a hold is never admitted after the arm; an arm with a wrong or
  stale token does not rotate; only the room-chosen active epoch is admitted.
  Replay against `Vxpipe.Gateway.Telephony.SourceEpoch`.
- **Slice 3 — MediaSession source request.** The room-facing request state
  (`idle` / `holding` / `held` / `arming` / `active` / failed-closed). Prove:
  the gate is never armed without a preceding acknowledged hold; a timeout or
  late acknowledgement never opens admission. Replay against the
  `MediaSession` handler transitions.
- **Slice 4 — Room cutover coordination.** The room's close → hold → retire →
  fresh origin → arm → reopen sequence, including transfer-hold overlap.
- **Slice 5+ — Participant/capability lifecycle.** Expand toward the broader
  room/participant/capability invariants once the earlier slices are stable.

## Tooling and gates

- `verification/` is a standalone Lake project with a pinned `lean-toolchain`.
- `bin/verify-lean` builds the project, runs the oracle generator, and fails if
  the regenerated oracle differs from the checked-in copy (drift gate).
- The Elixir conformance tests live in the owning umbrella child and read the
  checked-in oracle. They are tagged so the default suite does not require a
  Lean toolchain.

## Limits

Lean proves the *model*. It does not prove the Elixir matches the model beyond
the finite oracle, and it does not model OTP scheduling, process death or
message reordering unless a slice explicitly does so. Each slice states what it
does not cover.
