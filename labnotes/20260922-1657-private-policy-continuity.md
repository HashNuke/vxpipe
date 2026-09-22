# Private policy continuity

Follow-up to handoff checkpoint `bf60b027`, integrated by the parent as `5792d797`.
The parent authorized investigating/repairing the private revision-8-to-10 gap,
but required a proposed decision before implementing any normative change.

Read the workspace instructions, prior labnote, STS milestone and relevant
readiness/incremental-policy/human-transfer contracts. Inspected PrivateMedia,
PrivateSpeech, STT allocation/preparation, policy Authority/Barrier, connection
binding/retirement and candidate commit.

Finding: private actors are explicitly unregistered until adoption. Fresh actors
have no installed policy, so authoritative initial registration can avoid duplicate
base application, but existing APIs do not express the required lifecycle:
individual registration is critical too soon; grouped registration remains
noncritical after adoption. `monitor_enforcer` retains existing registration
metadata. A direct switch would therefore alter private cancellation or committed
failure semantics.

Replacing actors on unrelated revision gaps conflicts with documented provider
retention. Skipping snapshots cannot preserve revoke/regrant safety. The proposed
solution uses continuous authoritative delivery with explicit private registration
and atomic promotion at adoption; no second registry/history is proposed.

Recorded task breakdown and separate design review before tests/code in the
milestone and `docs/private-policy-continuity.md`. This is a proposal, not a repair.
No runtime files, tests, shared STS code, provider contracts or main-worktree files
were changed. No native/child tests were started; the prior controlled red remains
the evidence. Parent approval of the lifecycle amendment and narrow authority
write scope is required before implementation. Documentation diff checks only.

Parent subsequently approved the scoped amendment, including narrow Authority
registration/adoption changes. Updated the proposal, normative readiness and
incremental-policy docs and milestone before tests/code. Next: controlled native
gap red plus authority lifecycle reds, then implementation and bounded verification.

Controlled reds after approval:
- Native five-participant case pauses the preparation worker across the later
  monitor departure/rejoin. Baseline fails at returned-listener 250 Hz audio;
  output is released with 13 recovery packets (one test, one failure, 167.5 s).
- Three initial authority checks fail at the missing registration/promotion APIs.
- A private actor rejecting an unrelated revision still closed the authority;
  the focused red required local private teardown and one delivery to survivors.
- Further lifecycle reds proved omitted registered actors could be admitted and
  initial registration could outlast its original lease. Both were recorded as
  subtasks before implementation. One test initially used absolute deadline zero;
  corrected it to monotonic now minus one, since monotonic time may be negative.

Implementation:
- PrivateRegistration owns lease metadata/validation, stored only in Authority's
  existing enforcer map. The existing barrier delivers initial and consecutive
  policies. Private cancellation/rejection tears down only its group; required
  selection is promoted to critical connection-owned semantics before application.
- STT pair and each dormant Gateway media actor register with actual connection,
  phase, attempt, participant and original deadline. Refresh no longer reapplies
  snapshots. Removed speech demand retires its pair independently of media.
- Candidate selection covers all retained private receipt actors, including dormant
  media; omission, foreign scope/connection and partial group selection reject.
  Promotion cancels private owner monitors/timers so successful phase completion
  cannot retire adopted actors. Existing critical failure behavior is retained.
- Initial policy acknowledgement is bounded by the smaller original lease and
  enforcement budget. Expired registration cannot succeed. Failed private teardown
  alone has a bounded cleanup budget; this does not extend admission/preparation.
  Ordinary group behavior is otherwise unchanged.

The first child verification exposed a test fixture manually replaying already
installed snapshots. Recorded the newly exposed fixture task, then removed that
obsolete application only; strict snapshot checks remain unchanged.

Evidence so far: 12 focused native cases pass (including private actor/phase loss),
96 authority/STT/transfer-room checks pass, and 27 speech policy checks pass.
Two new actual-private-pair checks apply two authoritative revisions without worker
refresh: unrelated changes retain provider/token/generation; revoke/regrant closes
the old provider, invalidates old readiness and creates a new token/generation.
Both keep input closed and the original allocation deadline.
Final native rerun additionally asserts every private actor has the current policy
while the preparation worker is still suspended, before listener audio resumes.
Strict Credo and formatting passed at the first verification checkpoint; final
checks and commit remain pending. No full umbrella or external services were run.

The strengthened native rerun passed 11 cases and failed the added assertion with
an undefined test-local `Authority` alias, not a runtime policy/audio failure.
Added the local alias and moved the policy lookup before worker suspension, so
setup exceptions cannot leave the worker suspended. The three-case final rerun
includes that strengthened five-participant case plus both phone providers'
private decoder/output checks (the same Gateway preparation implementation).
Final authority-only recheck: 40 tests, zero failures. No run was cancelled.

Reproduction commands (each from its owning child; set `ERL_FLAGS='+S 2:2'`):

```sh
# apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/media_policy/authority_test.exs \
  test/vxpipe/call_engine/capability/speech_to_text_test.exs \
  test/vxpipe/call_engine/human_web_transfer_room_test.exs --seed 0
mix test test/vxpipe/call_engine/speech_to_text_media_policy_room_test.exs --seed 0
mix test test/vxpipe/call_engine/media_policy/authority_test.exs --only private_continuity --seed 0

# apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'five-participant handoff retains|human handoff gates (destination|participant) and .*silent_all waits|private WebRTC media stays gated' \
  --seed 0 --trace
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  test/vxpipe/gateway/telephony/outbound_phone_transfer_test.exs \
  --name-pattern 'five-participant handoff retains|prepares private decoder and output before room admission' \
  --seed 0 --trace
```

For the native red, apply only the worker-pause test change on `7715d4e7` (before
runtime repair) and select `five-participant handoff retains`. The returned-listener
assertion fails with recovery audio; prior diagnostic tracing identified private
revision 8 versus authoritative 10. The final stronger assertion observes all
private actors at the new revision before resuming that worker, then retains the
existing ordered cue/conversation assertions. No timeout was widened.

Final outcomes and limitation:
- 96 authority/STT/transfer-room tests pass (49.7 s); 27 speech-policy tests pass
  (15.4 s); final authority recheck passes 40 tests (3.8 s), all seed 0.
- The first twelve-case native run passed (215.6 s). After the stronger assertion
  was added, eleven cases passed and one failed solely on the missing local alias.
- With the alias fixed, both phone preparation cases passed and the five-participant
  case proved policy continuity before later timing out at `transfer.active` after
  the separate post-adoption listener attachment. This is not the revision-gap red:
  the returned-listener wait and private snapshot assertions had already passed.
- A bounded instrumented rerun of the same five-participant case passed through
  final ordered cue/conversation (one test, zero failures, 166.4 s) and emitted no
  handoff error. It proves the scoped continuity regression can complete, but does
  not diagnose or repair the distinct late attachment timeout. That finding stays
  open in the milestone; do not claim clean final root/native acceptance from a retry.
- Temporary diagnostic changes to HumanMediaHandoff were removed completely.
  Formatting, strict Credo and diff checks pass. No full umbrella gates were run.
  All test processes have exited; parent owns integration and serial final gates.
