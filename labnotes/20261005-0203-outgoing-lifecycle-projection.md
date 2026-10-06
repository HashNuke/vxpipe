# Outgoing lifecycle projection

Continued D6 after rechecking provisioning read-only. Both carriers' machine resources
exist; the test Tailscale node is stopped. No calls, purchases or AI/speech requests ran.
Preserved all existing work and unrelated cache-repair labnotes. No commits requested.

## Red and green evidence

- Storage initially rejected the new fact kinds: eight tests, three expected failures.
  Added bounded Calls payload validation and transactional lifecycle projection; eight green.
- Closure after HTTP failure initially retried `call_not_running`. Failed outgoing rows now
  accept archived closure without reviving their state; incoming failure behavior is retained.
- The initial engine archive fixture was invalid (missing queue/retry/drain settings), so its
  failure was not a meaningful emission red. Corrected it, asserted `room_opened`, temporarily
  disabled the new emitter and observed the expected missing-dial-fact failure. Restored
  emission: 24 outgoing room tests passed, seed 641719.
- Default closure precision test failed on `{microseconds, 3}`. Switched the default archive
  closure clock to microseconds. Engine/archive group: 32 passed, seed 968039.
- Added closure fallback, preparation failure and SQL-null tests: 18 tests, four expected
  failures. An answer timestamp with null outcome previously passed SQL CHECK. Corrected the
  additive timestamp migration, rolled back only version 20261005020300 in the test database,
  then reapplied it. No production/dev migration rollback occurred.
- Added preparation closure before HTTP failure: 19 tests, one expected `unknown` versus
  `failed` failure. Classified the explicit preparation failure; 19 green, seed 176955.
- The 43-test persistence regression group (outgoing, call-details source, storage resilience,
  call store) passed, seed 615866, before the last preparation-closure test. A first attempted
  group used two nonexistent file paths and ran only outgoing tests; do not count it as broad
  evidence. The corrected group above ran the real paths.
- Public inspection test first failed on missing outcome. Added outgoing-only metadata while
  preserving incoming shape. Corrected its timestamp expectation to the existing millisecond
  JSON contract: ten passed, seed 197607. The incoming exact-shape assertion remains intact.

## Decisions and remaining work

First retained outcome/timestamps win; late answers do not overwrite non-answer outcomes.
Archive closure fills missing local end evidence after unexpected termination. Preserve
answered; use unknown when a submitted dial is interrupted without outcome proof. Explicit
preparation failure has no invented dial timestamps. Payloads contain only approved outcomes.
Microsecond clocks avoid closure/start rounding inversions. Public inspection uses its existing
millisecond representation; call details retain microseconds. Added API/reference/runtime
documentation and a complete outgoing Morse STT/TTS example with the existing Google model.

Sent a pushnotify progress update. Root gates, example parsing and final milestone evidence
are pending. D6 is not accepted yet. D3 native STS and E carrier audio/ring acceptance remain.

Static root gates passed: formatting, warnings-as-errors compile, strict Credo (1,189 files),
and unused dependencies. Outgoing example parses through `CallSpec.new/2` with the ReqLLM
application started. An initial verification command used nonexistent `new/1`; a second used
`--no-start` without starting the model registry and rejected the selection. Corrected those
verification commands; no provider/model substitution or network request was needed.
Full umbrella test handle remains running; root acceptance is still pending.

## Accepted checkpoint

The full umbrella run completed successfully: 3,121 tests, zero failures, 98 excluded,
seed 219668, all nine applications. Counts: MCP 37, Providers 29, AgentRuntime 99,
Engine 1,859, Calls 130, Gateway 541, Artifacts 20, Persistence 210, Console 196.
Combined with the four successful static gates, D6 is accepted. No speech or source-cutover
state machine changed in D6; D5's previously accepted Lean evidence remains separate.

Verified local Markdown file links in the four changed guides. The outgoing example also
compiles to an outgoing plan with a 15,000 ms ring budget. Updated architecture links, API,
direction reference, runtime, milestone, index and harness. Only D6's two task boxes are
newly checked; D3 opening, E's three calls and the milestone index entry remain unchecked.
No rendered frontend changed; this checkpoint exposes metadata through existing endpoints.
No browser verification, paid call, provider audio or Telnyx signature match is claimed.

Next work is recorded in `native-sts-opening` labnotes. Preserve generated versus fixed
opening contracts and establish red room/provider boundary tests before implementing.

Final documentation check verified local file links in all seven changed guides/milestone
documents. Parsed the root log to confirm all nine result groups total 3,121/0/98. Final
`git diff --check` passed. Sent the accepted-checkpoint update with pushnotify. No commits
or resource mutations occurred during D6; the full goal remains active.
