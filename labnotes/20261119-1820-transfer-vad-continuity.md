# Transfer VAD continuity

The existing configured transfer case only checked observation before and after
transfer. It now uses the existing synthetic TTS startup gate to hold destination
preparation while the human is dispatch-held. Both local Silero modes send three
distinct PCM markers during this pending transfer, then one afterward. Provider
bytes, inference path, contiguous sample cursor, worker/run identity and delayed
playback acknowledgment correlation are checked. Duplicate bytes/inference and
extra commits are rejected after room completion and diagnostic drain.

The initial two cases pass without runtime changes. Review is in progress. A proof
gap found during source review is addressed by checking the diagnostic worker's
accepted timeline and processed boundary cursor for every marker, not just the
operational classifier cursor. The observer epoch must remain unchanged across
transfer preparation/completion. Verification of those stronger checks is pending.

Independent review injected a fallback stream/boundary reset and incremented the
worker epoch during transfer preparation. The original held-phase baseline still
passed, proving it did not cover entry continuity. The test now processes marker19
after the legitimate provider settlement but before initiating transfer. The held
phase must preserve that observer epoch, timeline and sample cursor; subsequent
markers must continue the same sequence. Review also reproduced a nil timeline
race in polling before the worker consumed its first frame; these awaits now retry
until an observed input exists rather than dereferencing nil.

The isolated fallback reset mutation passed the old fixture (1/1). Regenerated
against the strengthened fixture, it fails at the epoch-continuity assertion
(1 versus 0), proving the new entry anchor detects that loss. Static format,
compile with warnings as errors, strict Credo and unused-lock checks pass. Runtime
implementation is unchanged, so this checkpoint does not require a new Lean run.

Latest independent two-mode fixture passes 2/2. Review considers the specific
transfer-continuity proof complete; the broader lifecycle/stale-work matrix remains
separate. The final test also monitors actual room completion before authority
shutdown, waits for that DOWN and diagnostic drain, then checks duplicate traffic.
This strengthens the earlier authority-stop-only barrier to match the claimed
teardown scope. Final full configured selection and static checks are running.

The full configured selection exposed the other normal supervisor teardown race:
count_children exited with shutdown while the supervisor was stopping (22 tests,
1 failure in the existing on/off case). The drain helper now retries shutdown as
well as noproc; neither condition is counted as a successful drain, and unrelated
errors are still surfaced. The transfer cases themselves passed in that run.

## Final evidence

The final full configured diagnostic selection passes 22/22. Root format, compile
with warnings as errors, strict Credo and unused-lock checks pass. Documentation
links resolve and git diff --check is clean. Independent scoped Astra review is
clean, including the actual room completion barrier and narrow drain retry. The
transfer-continuity milestone task is checked; broader lifecycle/stale-work,
settings, UI and E/F remain unfinished. No runtime change, live provider test,
Telnyx change, full umbrella suite or deployment occurred.
