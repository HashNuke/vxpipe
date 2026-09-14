# Recording demand reconciliation

## Reproduced requirement gap

Continue the human-handoff private-resource task after `e05d8e4`. Prepared individual writers
already retire when their tracks disappear, but both candidate and installed track preparation
unconditionally require the full-mix writer. A policy forbidding recording therefore still waits
for a recording writer that has no permitted work.

The owning recorder lifecycle test stages a private joining writer, withholds writer readiness,
prepares a recording-denied candidate, and requires that candidate to contain no writer dependency.
It first fails because the full-mix writer remains in the resource list. Corrected an initial
test call to a nonexistent convenience API to use the existing readiness descriptor boundary;
the repeated red run fails at the intended writer-dependency assertion without that warning.

Candidate and installed track preparation now select no required modes when their actual policy
forbids recording. The existing staging diff retires unused private writers. Existing recording
streams remain available for permitted continuation; their handles and sequence counters are not
restarted. When permission returns, writer readiness becomes required again.

The owning lifecycle test passes through denial adoption, installed preparation, blocked writer
exclusion, no recorded denied audio, restored readiness gating and resumed full-mix output.

## Native verification

Extend the native handoff with denied and unrelated recording-policy revisions while recording
is the final blocker. An already connected participant is readmitted to apply the policy, so its
real output must also be held and cued. Denial must finish without ever releasing the withheld
writer readiness, retire the private destination writer and record no conversation. An unrelated
revision must retain that writer. Both keep the same attempt/deadline, room services, source
capabilities until adoption and existing speech/media actors, then exchange audio/transcripts.

Both native cases pass. The first run passed the denial case, but the unrelated-policy case
waited for the same writer-open notification twice: first to monitor retention, then to identify
its conversation stream. Keeping the already received stream ID fixes that test bookkeeping;
the isolated rerun passes without another production change. The complete owning recorder file
also passes: ten tests, zero failures.

The native cases retain the same preparation worker and deadline, compare the complete room
binding and source capability maps before adoption, and verify existing destination/observer
speech and media bindings after release. The readmitted listener receives its cue before caller
audio. Denial leaves writer readiness withheld throughout successful conversation; the unrelated
revision retains the private writer and receives recorded conversation on its original stream.

Logs: `vxpipe-recording-demand-red.log` (expected writer-dependency failure),
`vxpipe-recording-demand-green.log` (focused green), `vxpipe-recording-demand-engine.log`
(ten recorder cases), `vxpipe-recording-demand-native-first.log` (denial passes; duplicate
notification assertion fails), and `vxpipe-recording-demand-native-unrelated.log` (rerun passes).

## Human private-resource acceptance review

The human preparation owns a destination plan, private briefing TTS and an optional outbound leg.
For web handoff there is no outbound leg. The destination connection owns prospective STT;
candidate preparation stages mixer/transcript subscriptions and recording outputs. Existing
model/TTS and other room resource adapters are observed through `ResourceQuery`, rather than
reconstructed by candidate preparation. The source activation remains available until completion
or recovery. Human participants do not introduce model/tool/MCP activations in the inventory.

Existing engine/native acceptance proves prospective STT removal and unchanged STT retention,
including revisions before preparation, during cue playback and after adoption. Existing mixer
checks prove that removing a prospective listener retires only its new queue. Briefing TTS retires
after acknowledged playback, with late-event recovery covered by `e05d8e4`. This checkpoint fills
the remaining recording-demand gap, including retained stream identity on unrelated revisions.

This is evidence for the human private-resource cleanup task. It does not establish independent
destination model/tool/MCP readiness in AI transfers, complete changing-audience/re-entry behavior,
phone leg cleanup or the unexplained historical recovery failure. Those explicit tasks remain in
their delivery checkpoints; no acceptance requirement is removed or deferred by this review.

## Final verification and checkpoint

All five umbrella checks pass: format, compilation with warnings as errors, strict Credo,
`mix test --max-cases 4 --seed 235296`, and unused dependency locking. The suite contains
1,408 tests, zero failures and 16 integration exclusions: 642 Call Engine, 394 Gateway and
95 Console tests among the umbrella applications. The default Gateway lane includes both
new native cases; the public-URL integration case remains explicitly excluded.

Results are recorded in `vxpipe-recording-demand-gates-results.json` and the corresponding
per-check logs. Documentation links and `git diff --check` pass. There are no UI, dependency,
configuration or deadline changes. The other agent's documentation-site work is left untouched.

The human private-resource cleanup item is complete. Nineteen checkpoint tasks remain:
human two, AI three, phone six, changing/multiple listeners six, and final audit two.
The human slice and overall milestone remain open pending their full acceptance.
