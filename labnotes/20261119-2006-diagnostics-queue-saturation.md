# Diagnostic queue saturation and retained loss

## Reproduction and fix

Configured saturation checks reproduced a reporting defect in all four enabled
profiles: the call continued and resource limits held, but its run lost input
queue overflow evidence and persisted only lease expiry (plus partial-start in
reuse mode). Collection-off controls passed. The collector inspected only its
own output handoff counters, while saturation occurred in the source worker's
input handoff. A smaller Calls collector regression also failed specifically
because `observer_overloaded` was absent after authority expiry.

Added one sticky atomic flag to the existing shared handoff provenance. It records
overflow anywhere in the linked input/collector path while keeping local queue
counters and the first retirement reason independent. The flag is set before the
local overflow count so worker retirement cannot outrun publication of that loss.
The collector uses it both during polling and when persisting the terminal run.
No admission capacity, retry, provider setting, call control or source-policy
decision changed. A separate message was rejected because a saturated or retiring
queue could drop the very loss notification it needed to retain.

## Configured acceptance

Eight cases cover operational Silero off/on, collection off/on, and 512/4,096-sample
PCM. An enabled case suspends the already-attached diagnostic source worker, then
delivers 96 exact packets through the configured STT path. The small packets fill
the count limit; large packets reach the byte limit first. Every sampled pending
count/byte value stays within its configured bound; the suspended worker mailbox
stays within the packet limit plus eight lifecycle/timer messages.

Two canonical turns still produce their expected correlated responses while the
diagnostic worker remains suspended. Operational inference continues exactly once
per marker where enabled. Disable fences new capture; resume/termination releases
all queued bytes/counts and diagnostic source/inference/write slots. The persisted
run is incomplete and explicitly reports overload. Final drained checks reject
duplicate marker delivery/inference, extra provider commits or connection failure.
Off controls create no diagnostic run. No Telnyx files or live calls were used.

## Verification

- Configured red: 8 cases, four enabled failures at missing overload reason and
  four off controls passing. Green: 8/8, seed 455459, 13.9 seconds.
- Focused Calls collector red: 13 cases, one expected missing-reason failure.
  Collector/writer green: 28/28, seed 215164.
- Engine shared count/byte overflow tests were written before implementation;
  the new accessor was initially absent. Handoff/source-worker/source-supervisor
  green: 32/32, seed 937001. Existing release/re-admission behavior stays green.
- Broader Engine diagnostics plus ActivityRuntime: 244/244, seed 187775;
  Calls diagnostics: 52/52,
  seed 903477. Root format, compilation with warnings as errors, strict Credo and
  unused-dependency checks pass before the test-ordering correction below.
- Independent Astra xhigh review is clean after that correction; independent
  final CaptureHandoff 12/12 and Collector 13/13 pass, seed 0.

Review reproduced a race in the new collector regression: its real poll could
finish the overloaded run before the test advanced the fake clock, correctly
recording overload alone and failing the test's expiry assertion. The test now
suspends the collector before overflow, advances/closes authority, then resumes
with try/after cleanup. This explicitly orders the scenario without changing
production behavior. A separate suspected initial-frame issue was ruled out by
the real collection-off fixture: no source cutoff or activity-agent policy applies;
both probed cases passed. No speculative pacing change was made.

Final configured regression selection passes 29/29, seed 746372, in 42.1 seconds:
pending/late confirmation, the four mode-selection cases, all eight saturation
cases, observer crash/hang, blocked/error storage and missing-model cases.
Post-correction root format, compile, strict Credo and unused-dependency checks
also pass. No operational speech or source-cutover
state machine changed; Lean remains part of the final milestone gates rather
than being repeated for this diagnostic loss-accounting fix.

This proves synthetic count/byte saturation and its persisted coverage reason.
It does not establish measured RSS/CPU overhead, native execution performance,
acoustic accuracy or the entire stress gate. Those remain open in the milestone.
