# Manual commit timing

ContinuousSTT's stable post-commit draft flush sends an explicit manual commit even
in provider-VAD mode. Historical offline replay assigns supplied scenario offsets;
it does not capture a real live send timestamp. This is the applicable optional
manual timing path. Legacy manual-mode STT remains unsupported for automatic capture.

Five candidate modules are temporary files (not integrated; full root71378 remains
frozen/live): vxpipe_socket_commit_candidate.ex, vxpipe_scribe_socket_commit_candidate.ex,
vxpipe_continuous_commit_candidate.ex, vxpipe_capture_commit_candidate.ex and
vxpipe_report_commit_candidate.ex. The temporary vxpipe_commit_candidate_loader.exs
loads them only in the test VM, without writing beam files.

Socket.send_frame_with_receipt shares existing send/retiring/not-ready/failure
handling, returning a fenced timestamp immediately after successful transport send,
before reply. ScribeSocket exposes commit_with_receipt. ContinuousSTT optionally
uses that method while a diagnostic handoff exists; legacy transports use commit.
It normalizes successful receipt replies to operational :ok, emits through existing
ProviderTiming token/authority fences, and never retries legacy commit after an
attempted timed send. No provider commit strategy or wire payload changes.
CapturePacket accepts manual_commit_sent; LiveReport maps it independently from
text commit and merges repeated successful commits by latest time/sample count.

Red evidence: explicit flush lacked a receipt (1/1); socket API absent/readiness
clause absent (2/2); report rejected manual packet (1/1). Candidate green evidence:
- vxpipe_scribe_manual_candidate_test.exs:13/0 (including original timing cases,
  delayed reply retaining send time, revocation during reply, failed send without retry).
- vxpipe_scribe_commit_socket_candidate_test.exs with integration included:2/0
  through the actual local websocket server; identical commit bytes/count, revoked
  observation still sends, retiring/not-ready paths return existing errors.
- vxpipe_manual_commit_report_candidate_test.exs:1/0; manual/text commits stay
  separate, latest successful send revises duration, stale duplicates do not regress.
Test transport candidate is vxpipe_scribe_timed_transport.ex; its hold/fail controls
are test-only. Candidate review requested from Astra; explicit legacy fallback and
replacement/wrong-token receipt probes still required. Do not claim completion.

Follow-up temporary acceptance now passes15/0: explicit legacy-only transport
fallback sends exactly one ordinary commit with no fabricated receipt, and capture
replacement during a held reply cannot assign its old receipt to the new capture.
Legacy helper is vxpipe_legacy_scribe_transport.ex; these tests live in the same
manual timing candidate test. Existing ContinuousSTT, Scribe timing, ScribeSocket
and VAD socket tests with the candidate (including local integration lane) pass30/0
in vxpipe-manual-scribe-regression.log. Implementation review remains active.

Integrated the final reviewed candidates and all retained tests, including foreign
receipt token, unobserved receipt-capable transport and accepted-sample-prefix
cases. Focused integrated21/0; independent Astra xhigh rerun21/0 and review clean.
Broader Engine diagnostics plus inference-reuse/timing selection205/0. Root format,
warnings-as-errors compile, strict Credo and unused-lock checks pass. Full root tests
are deferred until milestone implementation is complete per user instruction.

Lean verification also passes for the integrated checkpoint.
