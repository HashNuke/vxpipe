# Morse room boundaries

Extending the persisted-service restart fixture to cover G's real remote room
failure and policy boundaries. Uses the owned Go binary at revision b922e71,
synthetic credentials and the same persisted publication in fresh Vxpipe VMs.
No real provider credential file is read and no hosted service is required.

The first two outage harness runs failed in the pre-existing origin ledger:
credential-free GET / probes arrived at loopback listeners, including the
inactive origin. The proxy now records only those empty-query, unauthenticated
root requests as separate root_probe events. All API and authenticated requests
still participate in exact route and origin assertions; no credential values
are logged. The third run reached the expected missing outage probe clause.

Added a fixture-only backend stop endpoint, with idempotent owned-process
cleanup. It is bound to loopback and is not part of the Go application. The
scenario injects an independently encoded dot plus word gap, observes partial
E, stops Go, waits for recognition-unavailable notification and ingress DOWN,
and verifies discovery fails at that origin. After room retirement it rejects
any final transcript, text reply, completed turn or reply PCM. The proxy ledger
also proves there was no TTS request. This passed with seed 512110 in 24.2 s,
including the existing persisted HTTP/HTTPS/WSS rollback checks.

The permission-mode harness initially failed because that mode was not yet
implemented. Before implementation, the user clarified that this should be
the existing Morse input/output hosted behind a small ElevenLabs-shaped API,
not a complete ElevenLabs speech platform. Removed the unimplemented permission
mode from this checkpoint and stopped expanding the acceptance harness. Existing
room policy tests continue to own ordinary permission behavior. The real outage
check remains useful evidence for the network boundary this provider introduces.

Final local acceptance uses the simplified Go revision 1d815f5: the persisted
origin/TLS/rollback plus outage test passes in 23.8 s (seed 582279). The ordinary
configured-room lane passes both repeated remote STT/TTS turns and interruption
of blocked remote output in 4.2 s (seed 141071). No production Elixir runtime
code changed in this checkpoint.

Root formatting, warnings-as-errors compile, strict Credo and unused-dependency
checks pass. The complete umbrella suite terminates successfully with 3,841
tests, zero failures and 148 exclusions (seed 899255). Go fixture formatting
and vet pass. Tests only add network-boundary acceptance; there is no speech
state-machine implementation change requiring a new Lean run.

The separate codec/TTS/STT interoperability lane also passes four tests against
the simplified binary (seed 653626), including the four selected PCM output
rates and repeated recognition. Together these establish the current supported
speech paths without the removed format/SDK matrix.
