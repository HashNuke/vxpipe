# Configured failure parity

- Added four configured synthetic Scribe cases: collection off/on with diagnostic classifier crash or hang. Exact provider PCM, two accepted transcripts and matching model responses are preserved; diagnostics disable drains workers without extra provider commits or connection failure.
- Owned classifier acknowledgement after both turns proves the hang is still pending before disable. Monitor-based termination confirms cleanup.
- Astra reproduced an assertion gap: duplicate provider sends passed all four original cases. Added post-drain duplicate refutes for all marker payloads; the same mutation now fails all four cases. Final scoped review is clean; independent baseline passes 4/4.
- These are acceptance tests for existing behavior, not a runtime behavior change. They remain old-coordinator evidence and must be ported during the single-owner room-service cutover. No milestone migration check is completed by them.
- Focused parent cases pass 4/4. Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass. Full configured fixture selection passes 10/10; umbrella suite deferred per user instruction. No live provider, Telnyx or deployment work.
