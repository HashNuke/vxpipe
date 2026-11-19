# Room turn landmarks

Provider/canonical speech references still needed a join to the room's generated
turn and command IDs. The room completion regression first failed on the missing
observation API. A separate capability regression proved the active capture handle
was not reaching the owning room with completion.

The capability now appends its current handoff only to turn-ended signals whose
allocation generation and installed global policy revision match the tap. Other
signals and revoked/off capture retain the existing envelope. Room handling keeps
its existing capability/identity/active-turn authorization, also requiring capture
ownership by that capability. At accepted completion, before response dispatch,
it offers speech allocation/ref, room turn/command IDs and a monotonic timestamp.
Rooms without an LLM text capability and native STS paths do not emit this evidence.
The packet has bounded detached identifiers; the worker forwards its original time.

Focused tests121/0 verify exact IDs/time, silent completion, duplicate/stale/foreign
identity rejection, revoked/unowned capture, saturation without control failure,
capability handoff propagation, detached backing binaries and worker forwarding.
Static gates and Lean pass. Broader room tests pass386/0. Astra xhigh review
returned no verified defects after eight independent probes, including nonempty
LLM dispatch, receiver death, STS exclusion and legacy envelope compatibility.
The preceding full umbrella run passed, but predates this checkpoint and the final
provider-link VAD ordering correction; it is not current-source acceptance.
This is actual room acceptance instrumentation, not automatic source admission or
collector persistence. First-response text/audio correlation remains open.
