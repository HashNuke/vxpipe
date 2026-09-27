# STS overflow test race

The full umbrella rerun with the GPT-Live barrier timeout test included hit a
failure in the pre-existing `STSCapabilityOriginsTest` overflow case. The
seventeenth provider `GenServer.call/3` exited `:killed`: the emitted event
reached the capability, which stopped on `:pending_caller_overflow` and tore
down the provider subtree before the fixture replied. That order is allowed by
the supervision contract; the test's unconditional `:ok` assertion was too
strong.

The test now accepts exactly the provider's `:killed` exit at this terminal
boundary while still requiring the capability's explicit overflow event and
monitored `:DOWN` reason. No runtime behavior changed. The focused test passed;
the next full umbrella run reported no STS overflow failure, although it
exposed a separate STT test race. The final umbrella run passed 2,868 tests,
zero failures, 61 tagged exclusions. Format, warnings-as-errors compile,
strict Credo, unused-dependency and Lean checks passed.
