# Completion egress benchmark

## Contract and implementation

The externally paced configured workload now produces synthetic speech through the
local Deepgram transport and a distinct acknowledged output sink per human source.
It measures canonical audio-turn completion publication to the room-authorized
AgentSpeechStarted publication, which follows the sink's playback-start callback.
This is a server egress acknowledgement boundary, not remote audibility. Provider
PCM or model text alone cannot supply that event. No production code changed.

The bounded test trace includes completion, dispatch and acknowledged egress with
room/incarnation, human source, connection, canonical turn/command and output id.
The separately retained public TextOutput.id is the TTS output id; matching it to
the acknowledgement avoids trusting an acknowledgement against itself. The full
public event trace also checks spoken text and per-human source identities.

The input pacing and fixed warm measurement cohort are unchanged. Both Elixir and
Python independently reconstruct all required events, reject missing/duplicate or
cross-source/output evidence and preserve slow final responses in nearest-rank p95.
The existing response_dispatch boundary and summary shape remain compatible. The
new response_egress contains the full three-stage population and count/p95_us.

The default smoke runner now requires valid egress evidence. Historical paired
reports explicitly use require_egress=False because that comparator's existing
contract declared its dispatch-only limitation; the parent owns its optional
paired-egress extension. That compatibility path does not weaken current runner
acceptance.

## Red-green and corrections

- Trace acceptance initially failed 2/3 tests for missing acknowledgement/output
  identity. The final focused trace suite passes 3/3.
- Elixir population acceptance initially failed its new undefined egress function;
  existing four dispatch tests remained green. Final Console population and
  configured acceptance pass 6/6, seed 383280.
- Python egress reconstruction initially failed two missing-helper cases; after
  implementation response tests pass 6/6.
- Smoke acceptance initially accepted a report missing egress (1 expected failure).
  After the default requirement, smoke tests pass 17/17. Historical paired tests
  pass 9/9 with the explicit compatibility option before the parent's extension.
- The configured two-human test first demonstrated text-only completion without
  any egress acknowledgement. Adding real fixture TTS/sinks exposed call-setup
  wait audio; the concurrent workload disables that unrelated sound. The final
  test exercises both humans sequentially through the same configured room,
  retaining distinct output identities and complete public spoken-turn traces.
- TTS completion emits AgentTurnCompleted directly; the public trace correctly
  expects seven events per spoken turn, not an invented AgentSpeechCompleted.

Logs: vxpipe-egress-trace-red.log, vxpipe-egress-summary-red.log,
vxpipe-egress-python-red.log, vxpipe-egress-smoke-red.log,
vxpipe-egress-configured-red.log, vxpipe-egress-console-final.log,
vxpipe-egress-trace-final.log, vxpipe-egress-smoke-green.log and
vxpipe-egress-paired.log. An intermediate extra-output trace experiment was
removed after confirming TextOutput.id already provides the independent identity.

Scoped Elixir formatting and git diff --check pass. No full suite, live provider,
Telnyx, native measured workload, deployment or commit was run. The actual warm
native measurement remains pending a reviewed checkpoint and quiet-host lane;
the focused configured test verifies the synthetic TTS/ack plumbing only.

## Independent review corrections

Review reproduced two invalid-artifact acceptance gaps. The egress validator
projected away dispatch before validating event order, admitting a reordered
completion/ack/dispatch list. Elixir and Python now enforce the original three-stage
sequence and per-room monotonic timestamps before either projection. The exact
reorder regression failed before the fix (Elixir 5 tests / 1 failure; Python
7 tests / 1 failure), then passed (Elixir 5/5; Python 7/7).

The smoke validator also admitted internally consistent egress evidence from a
different room/source than its dispatch evidence. It now requires identical
source identities, ordered canonical turn/command rows and completed/dispatched
trace projection; the optional historical output_id omission remains compatible.
The new cross-source/timestamp/command regression failed before implementation;
smoke tests now pass 18/18. Parent-owned paired validation opts into this check
whenever egress is present; its 11 focused tests pass. Review correction logs:
vxpipe-egress-review-response-red.log, vxpipe-egress-review-smoke-red.log,
vxpipe-egress-order-red.log and vxpipe-egress-order-green.log.

Final independent GPT-6 Astra xhigh re-review is clean. It reran the 36 focused
Python checks and inspected the final Elixir source and sink/identity linkage.
The focused Elixir order suite passed 5/5 after its red regression. This completes
the measurement-plumbing checkpoint, not the remaining native load acceptance.

## First native warm pair

After the reviewed egress checkpoint was pushed at `81b6aa2b`, one isolated
fallback pair (one room, one STT input) completed with no abort, cleanup errors or
retained databases. Both phases used identical recorded code/model hashes. The
[paired result](20261120-0226-egress-warm-pair.json) retains phase provenance.

| Metric | Off p95 | On p95 | Delta | Limit |
| --- | ---: | ---: | ---: | ---: |
| Ingress | 273 us | 279 us | 6 us | 2,000 us |
| Dispatch | 434 us | 506 us | 72 us | 2,000 us |
| Egress acknowledgement | 4,917 us | 5,210 us | 293 us | 2,000 us |

Each phase retained 625 ingress and ten response samples. RSS increased by
45,448 KiB against the 139,264 KiB budget. CPU increased by 0.101502 cores,
reported as advisory. All measured non-CPU gates pass. This is one warm pair,
not the complete repeated/cold matrix. It predates the subsequent immutable
call-start settings cleanup and is retained as historical measurement evidence.
The saved result's missing-evidence flags reflect its then-current scope; later
user decisions remove database CPU, inference coverage and model accuracy gates.

Independent Astra xhigh evidence review reproduced the saved pair exactly using
the historical comparator and original raw reports. Current validation preserves
all measurements and removes only the three superseded evidence flags.
