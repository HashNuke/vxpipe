# Missing model isolation

## Configured acceptance

The room-service matrix now exercises a failed diagnostic model load with local
operational Silero and collection independently on/off. The failure is injected
only into the benchmark runtime; operational Silero retains its synthetic working
classifier. Two real canonical Scribe fixture turns still emit the same transcript
and model-response correlation. Three distinct PCM markers reach Scribe exactly
once; operational inference occurs only when local Silero is configured.

Enabled fallback must actually call the failing loader and persist
observer_unavailable in its diagnostic run. Reuse and collection-off cases must
never call that loader. Disabled collection leaves no runs. Actual room completion
and diagnostic drain precede duplicate-byte/inference and extra-commit refutes.
The first focused four cases pass 4/4 with no runtime/provider changes.

This is one part of the existing failure-parity checklist, which stays open for
storage/saturation and remaining control-trace acceptance. It does not change
operational missing-model failure behavior or claim live provider support.
Independent scoped review and the final configured selection are pending.

Independent review's working-loader control replaces only the diagnostic load
failure with success. The fallback-enabled case then fails at the required
persisted observer_unavailable reason (one expected failure among four cases),
confirming the test distinguishes actual missing-model evidence from call success
alone. The first audio frame is paced after admission to avoid the established
same-millisecond cutoff race in collection-off fixtures.

## Final verification

The full configured diagnostic selection passes 26/26. Root format, compile with
warnings as errors, strict Credo and unused-lock checks pass. Independent scoped
Astra review is clean: normal cases pass 4/4 and the working-loader control has the
one expected failure. No runtime change requires a new Lean run. Documentation
links and git diff --check pass. The broader failure-parity and effective-status
tasks remain open; no live provider tests or deployment occurred.
