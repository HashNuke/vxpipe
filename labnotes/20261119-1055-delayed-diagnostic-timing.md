# Delayed diagnostic timing

Prerequisite40168099 is committed/pushed and Astra-reviewed. Its frozen root suite
is still active in session49144, vxpipe-progress-umbrella.log; latest results
include Engine2760/0 and Calls449/0, with Gateway running. No repository runtime,
test or build source has changed during that suite. Candidate changes are only
/tmp files compiled into separate test VMs via Code.compile_file (no beam writes).

Working candidate implementations:
- vxpipe_live_report_progress_candidate.ex
- vxpipe_source_worker_progress_candidate.ex

LiveReport coalesces acoustic progress per epoch with a fixed origin and monotonic
finalized bound. Acoustic landmarks/sample remain absent until the mapped provider
end and selected endpoint share finalized coverage. Provider and response stages
remain available. Boundary selection, including nil-offset uncertainty, is scoped
to mapped previous/current provider sample ends. Starts at the exclusive upper
bound belong to later audio. Resets close only progress intervals already present
at first reset observation; replaying a reset is idempotent. Closed epochs reject
later advancing progress. Coverage of an earlier completed turn remains usable.
The closed-epoch map participates in the retained-byte cap and is bounded by retained
progress packets. This remains a candidate, not production implementation.

SourceWorker candidate forwards the five metadata packet kinds during pending
inference, preserving charge/lease checks. It emits acoustic_progress after each
boundary batch and timestamps queued audio gaps with original frame receipt time.
Acoustic inference/reset processing stays sequential. Current reuse gap branches
for probability mismatches still use processing time; inspect their original
observed_at before integration.

Red/green evidence:
- Initial progress consumer contract failed invalid_evidence, then passed.
- Cross-epoch insufficient coverage and exclusive-end onset probes were red2/2,
  then green3/0 with the basic pending/revision/coalescing case.
- Astra probes reproduced later nil-offset uncertainty poisoning earlier turns,
  same-epoch reuse failure staying pending, opening reset misclassifying a new epoch,
  and earlier-turn delayed uncertainty poisoning a later turn. All reproduced
  locally before fixing. Duplicate reset replay and closed-epoch advancement were
  red2/11 before correction.
- vxpipe_live_progress_all_candidate_test.exs now passes12/0; latest log
  vxpipe-progress-bounds-green.log. It includes the independent review probes.
- vxpipe_worker_progress_all_test.exs passes24/0 with the blocked-inference
  timing regression, existing standalone tests (normal output capacity8, saturation
  test explicitly1) and reuse tests consuming/asserting progress packets.
- Actual configured LLM/Scribe fixture now passes1/0 pending row -> late acoustic
  revision -> shutdown drain -> durable reread. File:
  vxpipe_configured_latency_candidate_test.exs; log:
  vxpipe-configured-latency-candidate-tail.log. It uses real pinned Silero.
  The first three1s PCM chunks end in a partial model window;128 subsequent silence
  samples complete that window before awaiting the revised acoustic fields.
  This first turn is partial_start; do not claim full normal-turn/TTS acceptance.
- Existing LiveReport tests with candidate:17 tests,3 expected failures because
  successful acoustic fixtures omit the new required finalized progress evidence.
  Add explicit honest progress packets to those fixtures during integration; do not
  add a compatibility flag. Calls collector and Persistence latency fixtures also
  contain manually emitted boundaries and need the same contract update.

Next: wait for frozen suite completion, integrate candidates and retained focused
regressions, remove temporary fixture debug output, run affected suites and required
root gates, obtain final Astra review, commit/push. Review of latest report candidate
is active in /root/review_attachment_lease. No checklist item newly complete; no deploy.

Integration checkpoint: frozen prerequisite root suite49144 completed exit0, all
applications pass. Candidate implementations and reviewer probes are now in the
checkout. Configured fixture additionally proves a fully observed second turn and
matching response-text timing. Removed debug output/dependency-only PID assertion;
DB polling now yields using a bounded timer rather than spinning.

One additional report finding (missing mapping-origin lower bound) was reproduced
red1/1 and fixed; independent report review13/0 is clean. Worker reuse mismatch,
missing-prefix and implicit epoch transition now retain original probability
observation timestamps; reproduced red before correction, final worker review32/0
clean. Both kinds of queued gap retain their original time.

Retained tests are owned by Engine (report/worker), Calls (collector), Persistence
(durable revision) and Console (configured call). Existing hand-built successful
acoustic fixtures now explicitly provide finalized progress. Collector selection145
initially ran an adjacent passing test; corrected147 reproduced missing revision.
Persistence revision fixture also failed as expected before adding its progress.

Integrated Engine178/0, Calls46/0, Persistence17/0 and configured Console1/0 pass.
Root format, compile warnings-as-errors, strict Credo, unused-lock and Lean pass.
New frozen root suite vxpipe-delayed-timing-umbrella.log is running. Final
integrated report/configured-fixture review requested from Astra. No task newly
checked complete and no deployment.

Final integrated review found a weak fixture assertion: Elixir term ordering makes
`nil >= 0` true. Reproduced with an actual TurnTiming report having unavailable
room-to-text duration. Explicit integer assertions now precede both nonnegative
duration checks; configured fixture rerun1/0 and Astra final recheck are clean.
The first integrated root run18455 was deliberately stopped (confirmed exit1)
before this test correction; it is not acceptance evidence. The corrected frozen
root run uses vxpipe-delayed-timing-final-umbrella.log. No other code changed after
the earlier static/Lean checks; format and the changed fixture were rerun.
