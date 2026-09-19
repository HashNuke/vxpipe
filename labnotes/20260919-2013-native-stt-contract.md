# Native STT contract

Checkpoint A continues after accepted R (`4751bed`). Existing production rooms
remain on legacy providers; D must pass before B migrates STT into rooms.

## Decisions and red/green evidence

- Descriptor construction and the engine boundary both validate the closed STT
  format, readiness, endpointing, optional evidence and safe usage identity.
  Provider-specific public settings validation stays with the provider.
  Constructor-only validation is insufficient because structs can be built directly.
- Initial descriptor tests failed because the constructor/validator did not exist
  and malformed metadata started a provider. The next red pair showed mismatched
  readiness activating a session and unsupported speech-start evidence passing.
  All four pass after validation and event/descriptor agreement checks.
- Two event tests reproduced empty/invalid UTF-8 request IDs being accepted and
  missing optional eager-end/resume forms. IDs are now nil or 1..256 valid UTF-8
  bytes; optional forms require matching descriptor support and endpoint evidence.
  Existing native event names are retained and the design document is corrected.
- Five input-contract tests cover one bounded deferred provider slot, usage after
  acceptance/later failure, no usage on rejection, duplicate dispatch/late completion
  against newer input, and retired envelopes against replacement readiness credit.
  The first run also caught a test error: `send/2` needs the resolved channel PID,
  not its `:via` name. After correcting the test, two expected failures remained:
  `{:error, :busy}` was normalized to fatal failure and killed the provider.
  The minimal fix preserves only this known rejection; every other unexpected
  return remains a fixed fatal error. No automatic resubmission is added.
- Usage proof explicitly projects real Session acceptance into the existing usage
  accumulator from a test consumer. It proves A's boundary; production room usage
  wiring remains B. No per-chunk usage event or synthetic provider ID is needed.
- Input age means elapsed time since API entry. Raw binary input has no capture
  timestamp; existing ingress capture-age enforcement remains required in B.
- 76 speech tests passed after descriptor/event changes (seed 304). Final focused
  speech + existing Morse codec/transport/room + STT usage group: 102 tests, zero
  failures (seed 462672). This includes 81 speech cases.
- Root format, warning-free compilation, strict Credo and unused-lock check passed.
  At that point full root tests and final load diagnostics remained pending.
- Independent GPT-6 Astra xhigh review found one additional metadata inconsistency:
  eager-end support with `:none`/`:external` endpointing could never produce a valid
  matching envelope. A focused test failed because validation returned `:ok`; the
  validator now rejects that combination. Final focused group: 103 tests, zero
  failures (82 speech cases; seed 293622). The README example ran verbatim.
- Astra found no remaining A code blocker, conditional on final gates and accurate
  evidence. Its documentation corrections now distinguish the command deadline
  from the settled startup deadline and consumer usage from standalone delivery.
- First root run (seed 330044): Call Engine had 782 tests with one failure in the
  new contradictory-readiness assertion. It received safe `:session_failed`, not
  expected `:initialization_failed`: provider-death monitoring and the initializer
  failure notification race. Both retire the allocation. The test now requires
  either fixed safe category, rejected subsequent input and no ready event. This
  changes the test's over-specific reason expectation, not runtime behavior or
  load evidence. The failed run was stopped before completing remaining apps;
  a complete root rerun is required. This is not evidence of call instability.
- The seed-330044 focused rerun exposed another test assumption: optional-event
  startup awaited its asynchronous probe message for ExUnit's default 100 ms,
  despite this test exercising contract forms rather than a 100 ms startup
  budget. New A tests now explicitly allow 500 ms for notifications (well inside
  the default five-second API startup budget). Dedicated deadline/isolation tests
  retain their original timing bounds. An inadvertently started root rerun was
  stopped before proceeding; no passing result is claimed for either stopped run.
- The corrected focused group passed 103 tests with seed 330044. Root gates rerun
  with that same seed; only test observations changed after the final load runs.

## Verification method

User clarified that about 1 ms overhead is acceptable for reliability. Do not
optimize away lifetime/failure guarantees to claim speed. Continue checking tails,
deadlines, queues, loss and cleanup; this is not a waiver of instability evidence.
The priority is reliable startup and response quality at scale, not minimizing
every millisecond. This preference is not a new hard 1 ms ceiling on every sample.

Keep the original load harnesses, fixtures, repeat counts and legacy baseline.
Record full per-trial JSONs, including unfavorable observations. Measure audio
acceptance, first text and turn end; revalidate adoption authority and concurrent
fault containment. No capacity limit, hosted parity or TTS latency is inferred.

## Load results

- Final-source diagnostics ran serially, before starting the full umbrella suite.
  68,400 latency turns + 39,360 fault turns + 16,236 adoption turns = 123,996.
  Every exact content/order/identity/deadline/authority/teardown assertion passed.
- Latency initial run: 32 native p95 first-text/end 2.185/1.368 ms versus legacy
  1.706/1.271 ms. Held repeat 2 had maximum text/end 99.701/97.866 ms. Preserved
  [initial report](20260919-2013-speech-latency.json); the cause was not established.
- Final-source full follow-up: ordinary native p95 first-text/end 2.565/1.531 ms,
  legacy 1.677/1.246 ms; held native 2.225/1.460 ms. Held maxima 12.928/5.067 ms:
  the earlier spike did not repeat. Native audio-acceptance p95/p99 1.794/3.135 ms,
  legacy 1.490/2.273 ms. [Follow-up](20260919-2013-speech-latency-repeat.json).
- Faults: 72 trials, eight types, three repeats, 1/8/32 peers. Final maximum
  safe/teardown/replacement at 32 = 2.479/2.481/4.552 ms. One-peer teardown reached
  29.028 ms; safe observation maximum there was 0.214 ms. Minimum processing
  interval overlap with replacement at 1/8/32 = 0/6/15. All 8/32 trials overlapped;
  do not claim every one-peer trial did. Process count 245 throughout, memory
  80.5–86.2 MB. [Final report](20260919-2013-speech-faults-final.json).
  [Earlier passing report](20260919-2013-speech-faults.json) also retained.
- Adoption: 36 trials, 1/8/32 direct/adopted scopes, three alternating repeats,
  burst and paced input. 32 adopted healthy text/end p95 = 4.238/2.762 ms burst,
  1.438/0.815 ms paced. Direct = 6.173/3.159 ms and 2.762/0.626 ms. Adopted close
  p95 = 2.291/0.802 ms; obsolete-lease rejection = 0.414/0.205 ms. Process count
  245 every trial, memory 85.5–89.3 MB. [Final](20260919-2013-speech-adoption-final.json).
  [Preliminary](20260919-2013-speech-adoption.json) passed but a brief descriptor
  red test ran concurrently; final timings use the serial rerun. Burst tails
  were higher in both final modes; no causal latency improvement is claimed.

## Acceptance

All five root gates passed on the final reviewed source. The complete same-seed
rerun (330044) had 1,880 tests, zero failures, 40 excluded: MCP 37, Agent Runtime
95, Call Engine 782, Calls 117, Gateway 460, Artifacts 20, Persistence 184, Console
185. The focused 103-case run and unchanged load diagnostics also passed.

GPT-6 Astra xhigh reviewed the final test corrections and evidence. No remaining
A blocker was found; the independently checked timing/resource totals match the
retained reports. Documentation links, JSON validity, diff hygiene and the runnable
example passed proportionate checks. R/A are now accepted (2/9); D is next and
production room migration remains later. No UI or provider interoperability change
was made or claimed by this checkpoint.
