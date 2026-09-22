# STS tool retirement

## Scope and baseline

Started from clean runtime checkpoint `3c3456c6` plus execution-contract
clarification `5e7fed4c`; the only untracked file was this newly created labnote.
The same tool-boundary umbrella process remains live, with static gates and
1,084 Call Engine tests passing. Do not restart it or count it as proof of the
new changes. The user asked about parallel lanes; no new agent was started.
Continue direct work under their earlier instruction.

Expanded the existing ordered-tool-retirement milestone task before tests or
implementation. The current capability loses channel order in legacy owner
tuples, overwrites active duplicate references, has no pending bound and forwards
results without independently checking its association. Room-only map limits
and source checks do not fix those boundaries.

## Design review

Preserve acknowledged `Speech.Event` evidence with exact source identity, input
epoch and source audio interval. The room owns a scalar tool-event watermark;
do not keep every finished call reference forever. Retain admission scope for
cancellation, so a stale cancellation can retire only its matching association
and cannot publish under a replacement source. Recheck current policy for new
admission and provider-result delivery. Bound capability associations to 16 and
fail the owned allocation explicitly on overflow. Existing room saturation
rejection remains separate.

Hold fences the provider association, not an already-submitted engine invocation.
Worker ownership, bounded retained completion and provider-private continuation
remain the next execution checkpoint; do not turn speech interruption into
unapproved tool cancellation. Upstream adapters still own deduplication before
fresh semantic sequences; an old upstream event first observed after release
is not covered merely by owner-message epoch/sequence checks.

## Verification

The real-capability suite is red: **27 tests, four failures**. New checks
reproduce unbounded pending tools, missing ordered owner evidence, unknown
result forwarding to a permissive provider, and retained associations after
hold. The independent provider fixture acknowledges and reports tool results
so it cannot conceal a missing capability-side authorization check.

After the capability change its focused suite passes: **27 tests, zero failures**.
The room identity plus live Morse room suites then reproduce **33 tests, six
failures**: four absent ordered-event handler cases, one accepted legacy tuple,
and one live room crash on the new owner protocol. This is the expected room
integration red, recorded before implementing the room handler.

With the ordered room handler in place, the room/live suites narrow to **37
tests, four failures**: denied, revoke/regrant interval, absent participant and
unavailable policy still deliver an admitted result. This isolates settlement
authorization independently from admission before adding the current-policy
check. A separate snapshot protocol fixture makes policy changes acknowledged.

The independent Astra audit returned new concrete output-policy, recognizer,
Google-controller, hosted-sidecar startup and usage failures. Recorded their
methods/task breakdown in the milestone and reopened overbroad C/D completion
claims before implementing any of those repairs. Tool policy work already in
this checkpoint covers its separate current-policy admission/settlement finding.

The first joined capability/room/live green is **64 tests, zero failures**.
An additional room hold test then fails (**31 tests, one failure**) because a
provider that acknowledges hold without emitting cancellation leaves the room
association retained. The room now retires that association itself while
preserving its sequence watermark; this does not terminate submitted workers.
Strengthened the duplicate test with a later acknowledged tool-event marker so
it checks the original association before cancellation rather than just its size.

Final focused pass: **132 tests, zero failures**, seed 0, two BEAM schedulers.
Ran the capability/output-STT/caller-event suites; room tool/caller/output
identity, transcript modes, call and STS publication suites; startup activation;
and provider tool/turn-control suites from the owning Call Engine child. Logs:
temporary log `vxpipe-sts-tool-retirement-focused.log`. Format applied to the exact changed
Elixir paths; `git diff --check` and all 44 local links in the changed
milestone/contract/labnotes pass. Updated the provider contract with the
implemented boundary and explicit upstream/execution limits. Commit this
checkpoint before broader umbrella gates as requested; no new root result is
claimed here.

## Authorized parallel work

The user subsequently authorized native Codex subagents. Launched isolated
branches from `5e7fed4c`: Carver (Astra medium), `sts-parallel-gateway-20260922`,
owns the two Gateway handoff reproductions/repairs; McClintock (Astra medium),
`sts-parallel-load-20260922`, owns the actual ten-call comparative harness;
Goodall (Astra xhigh) reviews contracts/acceptance read-only at the same baseline.
No OpenCode/teammate process was launched. Parent retains STS tool runtime and
integration. Heavy native reproduction awaits completion of the existing root
run; final load measurement needs a separately coordinated quiet window.
Each implementation agent must record tasks before code, use red-green tests,
keep its write scope disjoint and return coherent commits for parent review.
