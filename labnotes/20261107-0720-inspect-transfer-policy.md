# Inspect interrupted room-frame transfer failure

The retained-MCP checkpoint's root run failed one existing Gateway acceptance
case: native repeated AI transfers with listener re-entry. Seed 362537 reaches
the second transfer, then reports policy_changed after 2 ms; the destination model
does not prepare. Existing bounded telemetry identifies `stage=push` and
`reason=interrupted`, followed by room-output owner death and policy-authority
shutdown. This is not evidence of a slow model startup. All other root application
suites pass; the same-seed isolated case passes (95.2 seconds, one test, 68 excluded).

Independent review traces the failure to OutputArbiter's room-push response path:
an intentional hold may clear the current room token before the native push's
successful response arrives. The arbiter maps that success to `interrupted`, and
SharedOutputPipeline propagates it as fatal. It also incorrectly rewrites genuine
native push failures to the same reason.

The correction belongs at the arbiter: preempted-token success or intentional
interruption returns success without finishing the old turn. Existing native-clear
completion remains the sole frame acknowledgement. Genuine failures keep their
cause, and interruption while the token remains current is still a failure.
Rejected: adding interrupted to the pipeline's immediate-discard list, which would
acknowledge before native drain and again after clear; increasing the test timeout;
weakening the fail-closed policy boundary.

Five focused regressions use the real native output, a message barrier before its
push, held pacing ticks, zero-capacity backpressure and injected RTP failure. They
cover delayed success, exact post-clear acknowledgement/new-generation playback,
failure before/after preemption, and interruption with/without intentional hold.
The red run reproduced four failures (wrong interrupted responses); the fifth
current-token interruption case already passed. The narrow arbiter correction now
passes all 39 arbiter/egress tests. Keep this correction separate from the staged
retained-MCP checkpoint. Lean is the output-handoff regression gate; the current
SourceGate model does not prove this reply-order race.


Independent implementation review found the source correction sound but identified
a test-gate weakness: its one-second fallback silently resumed native processing,
so scheduler delay could bypass the intended ordering. The gate now waits for the
explicit release message only; its registered on-exit cleanup always releases it
when an assertion fails. Existing bounded assertions fail a stalled test rather
than silently taking another schedule. All 39 focused tests pass again, and the
independent re-review reports no remaining actionable finding.

The first Lean attempt could not start because the optional toolchain was absent.
Installed the repository-pinned Lean 4.34.1 through elan, without changing shell
configuration or project dependencies. `bin/verify-lean` now passes: nine build
jobs, unchanged source-gate oracle, and one Elixir conformance test. Format,
warnings-as-errors compilation, strict Credo and unused-dependency checks also
pass. The full umbrella run with the original failing seed 362537 passes all
4,955 tests with zero failures (201 excluded), including all 875 Gateway tests.
This verifies the audio correction and retained-MCP work; the next checkpoint's
new duplicate-lookup regressions are a separate red lane.
