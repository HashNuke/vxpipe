# Google response adoption

Baseline `13f388be`: locally opted-in Google input origins are committed and
four root static gates pass; the five real-controller first/continued-response
tests remain deliberately red/uncommitted. No hosted calls. This labnote tracks
the next integrated response admission and assembly work.

Read capability `handle_event`, `Output.admit_reply`/`pending_turns`/
`admit_next_pending`, `ResponseOrigins`, shared `ResponseStarts`, Google
`STSResponses`, and the design prerequisites. The current capability grants
from caller `turn_ended` and queues only bare refs. Denied queued turns may be
silently popped. That cannot carry opted-in origin or response-specific
disposition. Added the concrete queue/external-gate/red-case breakdown to the
milestone and design review before implementation. The immediate next red
should use the real capability with an opted-in controlled provider, not the
full umbrella suite or a hosted Google call.

Google response-owner adoption remains required after the queue gate; this
design checkpoint alone does not close the five controller reds.

Focused red/green capability work: an opted-in `response_started` initially
terminated the capability as an invalid provider message. Added exact event
acknowledgement and response-reference admission; caller end now only settles
caller evidence for opt-in. First tests for grant, held-origin discard, and
external activity were red, then passed. Additional reds reproduced a queued
response stranded behind unresolved activity on hold; queued responses retained
across policy revoke and across a policy revision while the output slot was
busy; and stale external activity blocking a new input epoch. These now pass.

The capability stores opted-in pending entries with response reference, context
and immutable accepted fingerprint, rechecks the source/epoch and both policy
intervals at grant time, and rejects only the denied response. Policy, hold
and release paths retire stale entries even while the slot is busy. Accepted
external activity is origin-scoped; stale activity clears on origin change.
Legacy caller-end admission stays separate. Bounded queue tests exercised 16
pending starts and capacity recovery; three sequential responses verified
oldest-first replay through the one credited output slot. The 19-test focused
origin file and 94-test broader capability group passed locally before final
format/review. No hosted calls or full umbrella red run.

Independent Astra xhigh review found two actionable misses. Reusing the same
supplied epoch after hold made the old fingerprint current again, and
provider-detected `speech_started` did not gate a same-origin response. Both
were added as explicit milestone subtasks before fixes. Focused real-capability
tests reproduced both red. The fingerprint now includes a capability-local
lifecycle revision changed on hold/release, and the capability tracks exact
open caller speech refs (rather than a single overwritten ref), clearing only
the matching accepted end; opt-in dequeue rechecks that gate. Current focused
origin file: 21 tests green. Broader capability group: 97 green. Re-review is
pending.

The re-review identified another candidate: unresolved provider speech refs
could grow beyond 16 when caller forwarding is suppressed by `:human_stt`.
After adding the milestone subtask, a focused 17-start test reproduced the
unbounded set red. The opt-in gate now has its own 16-turn limit and stops the
capability with `:pending_caller_overflow` on the next distinct start. The
focused origin file is 22/0. This independent bound is not delegated to
caller-event forwarding, which can be bypassed by source selection. Final
review and broader gates are still pending.

A final read-only review raised a possible fail-atomicity fault: the 17th
speech start could publish caller evidence before the independent overflow
check, after caller-forwarding capacity had been freed by stale evidence.
Added the milestone subtask and reproduced this exact sequence red: the room
owner received `vxpipe_sts_input_event` for the rejected start. Moved the
bounded unresolved-speech admission before `CallerEvents.forward/2`; the
focused 23-test file is green. Review requested again. The test waits on
project-owned owner messages, not sleeps, to synchronize the first 16 starts.

Final Astra xhigh source-only re-review found no remaining actionable issue
in the capability diff. The relevant capability group passed 99/0. The
milestone keeps its first queue child/parent open because source-replacement
integration and Google response-owner delivery remain unproven; the two
implementation/lifecycle queue children are checked with this evidence.

Post-commit static checks after `3b3bdd76`: format and warnings-as-errors
compile pass; strict Credo reports `Output` at 872 lines versus the 800-line
limit. This is an architectural hygiene gate, not a response-behavior failure.
Added a milestone refactor task before code changes. Extract cohesive response
admission/queue ownership, keep the focused capability group green, and rerun
the static gates after a follow-up commit.

Refactor committed as `13673cdd`: `ResponseQueue` owns admission/retirement,
and `Output` delegates while retaining playback and recognition. `Output` is
691 lines and `ResponseQueue` 194. The 99 focused capability tests remained
green, and independent Astra read-only review found no reproducible behavior
regression. All four root post-commit static gates pass: format, warnings-as-
errors compile, strict Credo (1,092 files/no issues), and unused dependencies.
Root `mix test` is deferred until the five deliberately red Google controller
cases are implemented; these static gates do not claim milestone completion.
