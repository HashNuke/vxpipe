# VAD barge-in timing

## Work in progress

The primary missing metric is human acoustic onset to acknowledged server egress
stop for the interrupted output. Source/clock/output association, persistence and
UI are still pending; no acceptance task is complete yet.

Two prerequisites are implemented with focused red-green evidence:

- Output.interrupt_with_receipt/4 timestamps a successful sink reply before
  retiring outstanding output and replying to its caller. Existing interrupt/4
  retains its result shape. Rejected stop requests receive no timestamp. This is
  the server acknowledgement receipt, not remote audible stop.
- SpeechToText now forwards the current diagnostic handoff with turn_started as
  well as turn_ended, under the existing allocation, input-interval and live-grant
  fences. A closed handoff is still omitted. InputTurns has not yet been wired to
  consume the onset handoff for interruption evidence.

Tests failed first for missing receipt API (two failures) and missing onset
handoff (one failure). Both focused files now pass: 29 tests, zero failures,
seed 74272. Logs: vxpipe-barge-stop-red.log, vxpipe-barge-onset-red.log,
vxpipe-barge-boundaries-green.log. git diff --check passes. Broader relevant and
final checks are pending; no claim is made for unrelated unfinished egress tests.

## Integration decisions

Review confirms TTS.interrupt waits for provider cancellation after the sink stop;
observing RoomAuthority return would overstate delay. Carry the sink receipt into
an offer made before Session.request_cancel. Associate with the interrupting
human's handoff, not the old response's handoff: different humans/previous turns
must remain distinguishable. Current TTS :wrong_turn fallback {:ok, 0}, no current
request and queued-only requests must not fabricate stop evidence. Retain actual
playback-start acknowledgement; request admission does not prove audio played.

Continue with one coherent integrated checkpoint, not a commit per timing field.
Prior uncommitted egress harness changes and the unrelated effective-status note
are preserved. No Telnyx or live-provider tests; no production deployment.

## Capture integration progress

InputTurns now carries the interrupting input's allocation/turn references and
new canonical IDs through optional AgentOutput.interrupt/3. The ordinary text and
unobserved interruption paths retain their prior API and semantics. TTS retains
its first accepted playback-start receipt per request and offers stop metadata to
that new input's handoff before waiting for provider cancellation. Packet identity
separately names the old agent/human/connection/turn/command/output. Wrong-turn,
unstarted and revoked cases cannot fabricate successful evidence.

SourceWorker forwards this bounded metadata while inference is pending, releasing
its charge. LiveReport retains it under its allocation/turn/output identity with
existing count/byte limits, rejects foreign generations and conflicting duplicate
receipts, and does not fabricate a completed human turn. Acoustic onset projection,
durable incomplete/pending evidence and API/UI exposure still need implementation.
This capture path is not yet a completed metric; no new milestone task is checked.

Focused red-green evidence: room identity test 15 pass/1 fail then 16/16;
SourceWorker metadata test 1 expected failure then 19/19; pending report retention
22 pass/1 fail then 23/23. Combined current selection passes 62/62 (seed 728334)
in vxpipe-barge-capture-green.log. Capability plus existing semantics previously
passed 45/45; generated-test typing warnings were removed by using test tags and
the 4 new diagnostic tests rerun clean. Independent GPT-6 Astra xhigh foundation
review passed 33/33 and returned clean; extended room/metadata review is pending.
All commands are terminal. No full suite, production deploy or live provider run.

## Primary-metric scope cleanup

Removed the root agent's unfinished, uncommitted completion-to-egress performance
harness experiment from eight test/script files, restoring their last committed
completion-to-dispatch behavior. Its patch is retained as
vxpipe-unfinished-egress-harness.patch for reference. It was not connected to the
configured workload and had outstanding failing output-identity tests; no success
was claimed. This does not remove the committed performance harness or waive its
remaining paired-measurement acceptance. The two primary VAD measurements remain
the implementation priority. Other agents' work and the effective-status note
were untouched.

## Onset projection and accepted-start records

BargeInTiming now joins the interrupted output with a unique acoustic onset inside
its source sample interval and playback/request time window. The baseline is the
onset estimate, not confirmation. Open speech with late confirmation is supported;
missing/ambiguous boundaries, unavailable stop, unstarted output, uncertain timing
and inference resets produce nil duration with reasons. Evidence explicitly names
server egress acknowledgement and retains the interrupted response identities.

The live report derives the nested bounded barge_in record and increments the same
turn revision when late onset arrives. An accepted room_turn_started packet now
creates an incomplete record before STT completion; no completion landmark is
invented. These changes passed 31 projection/report tests and 62 combined report,
worker and room tests after focused expected failures. Current follow-up review
is checking pending-record coverage accounting and overlapping interval ownership;
those checks must finish before this checkpoint is accepted.

Parallel implementation authorized by the user: storage/API implementation passes
40 focused tests; frontend implementation is undergoing rendered Storybook
verification; configured real-room acceptance is being added separately. No new
milestone task is checked solely on these partial component results.

## Independent review corrections

The reviewer reproduced four source-association/accounting defects. Permanent
regressions were added before the fixes:

- Accepted-start rows now count as observed records, matching durable coverage
  accounting; they still contain no invented completion landmark. A Calls coverage
  regression failed with counter_mismatch and now passes.
- Barge-in onset ownership considers all finite canonical source intervals. An
  onset inside competing intervals is ambiguous rather than available. The
  overlap regression failed first and now passes.
- A pending provider interval without a known end cannot borrow an older turn's
  onset from the source origin; duration stays source_interval_unavailable until
  the source interval is proven. The {0,nil} regression failed then passed.
- Accepted starts now fence provider-to-canonical redirects in both arrival
  orders, just as completions do. Both regressions failed before the guard change;
  the final report selection passes30/30, seed892375.

Independent GPT-6 Astra xhigh backend review returned clean after these fixes.
It independently ran75 Engine tests and Calls model/coverage checks, reviewed the
last redirect correction and retained reproductions, and found no remaining
backend issue. Frontend and configured acceptance are separately under review.


## Checkpoint verification

Independent combined backend/configured review is clean: the final cross-human
case reran 1/1 (seed 0), all four retained review probes passed, and the holding
fixtures and operator documentation were inspected. Frontend re-review is clean
after the sub-millisecond correction, with 37 component tests independently rerun.

Root format --check-formatted, compile --warnings-as-errors, credo --strict and
deps.unlock --check-unused all pass. bin/verify-lean builds 9 jobs without oracle
drift and its focused source-gate conformance test passes 1/1 (seed 189098). Logs:
vxpipe-barge-format.log, vxpipe-barge-compile.log, vxpipe-barge-credo.log,
vxpipe-barge-deps.log and vxpipe-barge-lean.log. No full umbrella test run or live
provider run was performed. The milestone records completed implementation while
keeping broader acceptance and final deployment open.
