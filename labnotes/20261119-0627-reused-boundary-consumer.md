# Reused boundary consumer

The existing source worker now supports operational_reuse without an inference
admission handle or model runtime. It consumes timestamped probability evidence
and accepted audio using the same clock mapping and output format as standalone
observation. A separately charged pending queue handles cross-sender delivery of
probabilities before audio. Provider resets retire waiting old evidence; late
retired-epoch results are ignored. Missing probability windows or audio gaps
invalidate the epoch rather than joining unrelated speech.

Source-pool admission retains LLM-only eligibility and bypasses diagnostic model
resources in reuse mode. Initial consumer tests failed because admission was
required; the factory test separately failed against an absent runtime. Both now
pass. A saturation regression also failed before input overflow/invalid counts
were made terminal for observers. This avoids retaining a full queue indefinitely
when matching audio is lost. Cleanup releases retained reservations.

The actual operational adapter feeds this consumer in an integration test: one
classification produces normal onset and mapped diagnostic onset, and revoking
diagnostics leaves the next operational classification intact. Affected tests119/0;
static checks and Lean pass. Astra xhigh final re-review is clean. Automatic source
attachment, persistence/correlation and configured-call acceptance remain pending.

The prior umbrella run completed with exit2: Engine2638, Calls424, Gateway891 and
Console591 tests passed, while Persistence exposed an OAuth repository shutdown
race. Independent review reproduced that separate issue; its fix is tracked in
repository-shutdown-race labnotes. That run predates this consumer change.

Astra reproduced a false complete endpoint when only a suffix of a multi-segment
probability packet had captured audio. Its first unmapped endpoint cleared partial
state, allowing a later endpoint to look complete despite an unobserved onset.
The retained regression failed before a full-window coverage check was added.
Once the packet end is captured, an absent prefix invalidates the epoch rather
than advancing boundary state. Input producer ordering and gap invalidation make
that prefix unrecoverable. Focused suite119/0 and static/Lean checks pass after fix;
Astra xhigh final re-review is clean: 19 focused tests plus two additional
multi-packet/reset-recovery probes pass.
