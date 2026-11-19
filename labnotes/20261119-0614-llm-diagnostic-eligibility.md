# LLM diagnostic eligibility

The user restricted diagnostic VAD to LLM-based agents. The existing source pool
factory now requires a resolved agent with model inference and no speech-to-speech
capability before looking up diagnostic runtime resources. Unknown participants,
humans, STS agents and mixed LLM/STS declarations are rejected. The resolved plan
is removed from worker options after checking eligibility.

The first test attempt failed on incomplete enforced struct construction; fixtures
were corrected before establishing the meaningful red result: unsupported input
returned `unavailable` instead of `unsupported_agent`. The guard makes that test
pass. Existing worker capacity/replacement and real Silero sample correspondence
remain green: 11 tests, zero failures. Format, warnings-as-errors compilation,
strict Credo and unused-lock checks pass. Independent Astra xhigh review is clean (11 tests, zero failures).

This is the coordinator admission boundary, not a claim of automatic live capture.
Production source attachment and operational-reuse admission still need to enforce
this same scope when wired. The full umbrella run is in progress; prior root runs
have known fixture-ordering and idle-admission failures under investigation.
