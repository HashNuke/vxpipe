# Diagnostic room candidates

A future automatic coordinator needs a current room-owned view of eligible sources,
not a copy of the resolved plan. DiagnosticSources.query now requests pages of up to
32 current main-admission human STT bindings from the selected, present LLM agent's
ready room. It excludes held/absent participants, private transfer preparation,
native STS/mixed capability declarations and unsupported legacy state. Returned
identity and eligibility evidence contain no prompt or provider configuration.
The query performs no dependent process calls inside RoomAuthority.

Source discovery already records a global policy revision, but the original attach
API used whatever revision was current on receipt. The new five-argument attach
checks the discovered revision before existing source/allocation/grant checks.
This prevents accepting a stale discovery after a policy transition; the existing
four-argument API remains available for its current direct callers.

Red23/5 established missing query/attach APIs, then focused23/0. Broader tests403/0
passed before a mechanical extraction of snapshot construction into Room.Snapshot.
That extraction keeps RoomAuthority under the repository's800-line module limit
without changing construction behavior. Static root gates now pass. Lean passes. Final broader verification passes403/0. Astra xhigh review is clean:
23 focused tests,25 independent/retained room tests, and8 snapshot/raw-room tests
pass. Seven independent probes cover real configured-room compatibility,67-source
pagination, exact selected-agent resolution, privacy and attachment fences.

This checkpoint supplies current candidates and a policy-fenced attachment API.
Automatic enumeration, source lifecycle coordination, collector/report persistence
and configured-call acceptance remain open. No live observer was enabled.
