# Automatic diagnostic attachment

The source pool can now own a coordinator that scans registered rooms, obtains
current LLM/human candidates, probes the next accepted source, revalidates the
candidate and starts/attaches a source worker through an injected collector port.
One pending probe and the existing source-worker capacity bound retained work.
All lifecycle calls stay outside room/audio callbacks. Defaults:250ms scan,
250ms capability discovery,500ms coordinator expiry,16 sources (cap32). Registry
selection uses a transient room-identity list; its load overhead remains an E gate.

The same isolated one-for-all pool retires workers before coordinator replacement;
workers also monitor the coordinator. Revocation closes grants; source replacement
permits a fresh run. The collector interface carries coordinator ownership for its
own bounded lifecycle and returns a capture handle; Calls/database dependencies do
not enter Engine. No app-level wiring is enabled until the live collector exists.

Initial red2/2 demonstrated missing coordinator pool support. Focused3/0 now proves
automatic initial discovery/attachment, no work while off, unique active attachment,
disable preserving provider admission, source replacement with a new run, and
coordinator failure leaving speech operational. The fixture uses real STT and worker
processes plus the actual room-query callback through a small test room process.
Configured end-to-end report persistence remains unimplemented. Final review and validation are recorded below.

Independent review reproduced six lifecycle/fencing failures plus an overlong
capability discovery wait. All reproductions were retained and failed before fixes.
Active candidates are now audited round-robin even at capacity; candidates are
checked after collector startup and again before bind. A cap-owned one-use source
proof prevents old-epoch attachment after later accepted audio; it is scoped to
allocation, policy, settings grant, source and a5s deadline. Readiness receipt checks
the500ms pending deadline. Coordinator discovery/bind RPCs use250ms budgets.
Coordinator-owned worker output grants close during worker retirement, including
coordinator kill. A separate invalid-handoff regression proved/fixed a missing
callback fallback that could otherwise stop the speech capability. Original review
probes pass9/9; the final independent re-review passes13/13 with no findings.

Final review also reproduced false retirement when newly added connections moved
a healthy source beyond its old page. Revalidation now uses an exact connection
lookup with the same room eligibility checks. A separate retained regression
proved that missing optional track metadata could crash discovery after ordinary
provider admission; invalid metadata now skips discovery without changing speech.
Both regressions failed before their fixes. Final affected tests142/0, root format,
compile with warnings as errors, strict Credo, unused-lock check and Lean pass.
Astra xhigh independent final review13/0 is clean. The prior full umbrella run
passed but predates this checkpoint; a new current-source run is required.
