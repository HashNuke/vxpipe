# Reuse source correspondence

Operational inference previously emitted only reset-relative sample positions.
A source starting at sample 32000 produced diagnostic offset zero, insufficient
for unambiguous receipt-clock mapping. A regression using the actual operational
adapter failed on that missing mapping before implementation.

The existing tap now records accepted normalized frame positions, without copying
PCM or executing another model. Results carry both detector-relative and absolute
normalized source sample positions. Context is fixed at submission, so late
results retain the old epoch and origin after provider settlement. Continuity gaps
emit a notice and invalidate source mapping until a subsequent operational reset.
Raw byte API input has no transport sample identity and remains explicitly unmapped.
Admission rejection does not advance the diagnostic position.

The operational normalization, detector pending bytes, resets, inference admission
and speech-control behavior remain unchanged. The capture packet allowlist accepts
the new bounded numeric tuple. The consumer still needs to combine these tuples
with accepted source audio and discard incomplete/cross-reset evidence; this is
not complete configured-call wiring.

Affected diagnostics/operational speech tests: 111 tests, zero failures. Includes
nonzero source origin, successive provider resets, gap invalidation, old in-flight
results after reset, and existing disable/mid-inference/odd-byte cases. Static
root checks and Lean pass. Astra xhigh review is clean: 10 checked-in tests and
14 independent probe tests pass, including five additional partial-window, 48 kHz,
gap recovery, raw-input poisoning and queued-reset cases. The earlier umbrella
run remains in progress and predates these changes.
