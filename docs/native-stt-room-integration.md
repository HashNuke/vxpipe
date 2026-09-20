# Native STT room integration

## Decision

Each attached audio connection owns one temporary supervision tree below the room capability
supervisor. That tree contains a speech capability scope, the room's STT policy capability, its
bounded media ingress, and every semantic provider allocation started for the connection.
The capability remains the room policy and turn-projection boundary. It consumes acknowledged
`Speech.Event` values and projects them into the existing room signal contract, so room authority,
barge-in, attribution, readiness, and transcript routing do not gain a second state owner.

Morse STT is selected directly as `Provider.MorseCodeSTT.Session` and requires no transport
configuration. Deepgram remains wire-compatible during checkpoint B through the private
`Capability.SpeechToText.LegacyBridge`. The bridge owns the legacy adapter and socket inside the
same allocation-local session. It is not selectable from a call spec and is removed when the
native Deepgram session lands in checkpoint C.

Prepared semantic sessions use the capability as their internal lease authority while the
existing policy preparation continues to monitor the external preparation owner and deadline.
Before adoption, the channel accepts provider readiness but discards transcript and turn events.
This prevents a delayed or unsolicited prepared-provider event from becoming visible after a
later policy commit.

## Rejected alternatives

- A shared application speech supervisor would couple unrelated calls and retain the failure
  boundary that this migration is removing.
- A participant-owned speech tree would assign connection audio lifetime to the wrong owner and
  complicate connection replacement and transfer preparation.
- Rebuilding media policy, ingress, turn detection, or barge-in inside the session layer would
  create duplicate authoritative state. The existing room capability keeps those responsibilities.
- Keeping Morse behind the legacy transport would prove only the old wire contract and would not
  exercise the semantic session in a real room.
- Adding a new externally stored allocation wrapper for the capability/ingress pair would
  duplicate connection state. The connection tree is queried only for exact teardown; the room's
  existing capability and ingress PIDs remain its public bindings.

## Implications

Loss of the speech scope closes the capability and ingress through the connection tree's
`:one_for_all` policy. A standalone ingress still reports `:capability_unavailable` when its
capability disappears; inside the owned connection tree both children terminate with the tree.
The room authority retires the unavailable connection-local enforcers and leaves other
connections in that room running. Explicit room teardown terminates each complete connection
tree once. Native provider replacement stays within the two-slot local scope, and prepared events
remain fenced until adoption.

The direct legacy `Capability.SpeechToText` construction path remains for unmigrated internal
tests and consumers. Planned rooms no longer use its global connector path: hosted STT is wrapped
by the local bridge. Checkpoint C removes the bridge, and the final cleanup checkpoint removes the
remaining legacy-only fields and global connector supervisor.

## Verification evidence

The B1 room test first failed at plan validation when Morse was configured without a transport.
After integration it completes two attributed caller turns and two decoded spoken responses
through the semantic STT session. Focused tests cover prepared replacement, denial, owner loss,
stale cleanup, hosted bridge cleanup, exact connection-tree teardown, bounded final-event drain,
and the pre-adoption transcript fence. Held native and bridge initialization do not delay a
healthy native connection. Allocation-tree and capability-tree loss close only the affected
connection tree while a sibling connection in the same room completes recognition and exact PCM
playback.

GPT-6 Astra xhigh checkpoint review found retained private initialization in supervisor arguments,
mixed readiness generations and a pre-claim owner-loss cleanup gap. Red tests reproduced each
finding; the opaque one-shot private handoff, selected-generation candidate graph and creator
monitor repaired them. Final review found no remaining P0/P1/P2 issue. Load verification was
capped at four concurrent calls, half the host's eight logical CPUs. The ordinary
lane completed 40/40 turns with exact text, identity, event counts and PCM output. Burst p95 was
0.361 ms ingress admission, 1.871 ms first text, 2.550 ms turn end and 0.474 ms first audio. Paced
p95 was 0.442 ms admission, 0.520 ms turn end and 0.242 ms first audio; its 240.904 ms first-text
measurement includes scheduled audio delivery. A four-room paced stress lane kept every healthy
room complete while separate rooms committed a policy change and interrupted blocked playback.

The host had unrelated load, so these measurements prove the bounded workload and control
semantics, not production capacity or a hardware-independent latency limit. The machine-readable
reports are in the checkpoint labnotes. Umbrella gates remain pending.
