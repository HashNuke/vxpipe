# Tenant opening credentials

## Checkpoint scope

The previous goal turn made progress: committed the shared inline schema/runtime cutover as
`28af909`, with all five root gates green (1,489 tests, zero failures, 30 exclusions). The
worktree was clean at this continuation. Checkpoint 1 is verified; checkpoints 2–7 and final
independent implementation review remain open. The requested reviewer's quota limitation does
not prevent the next implementation/acceptance slice.

Start checkpoint 2 with the existing independent opening lifecycle. Verify a persisted human-entry
call using a named Deepgram opening credential, separate from caller STT. Test missing opening
bindings before database writes, actual private PCM playout, input gating, and subsequent cache
reuse/revocation. Keep source recovery and transfer scenarios in their next coherent commit.

## Inspection and decisions

- Read the current milestone, the implemented opening prerequisite, and its linked opening
  contract. The runtime already routes opening preparation through the tenant credential source.
- The opening contract document still describes retired schema/profile/application credentials;
  update its current contract with this checkpoint and retain dated evidence as historical.
- Use real tenant provisioning, encrypted persistence, definition publication and prepared-plan
  reload, followed by in-process Deepgram transport doubles and the existing supervised output
  sink. No live provider request or browser change is part of this backend acceptance slice.
- Added the missing-binding and human-entry integration assertions before any production changes.
  If existing shared wiring satisfies them, record that evidence instead of changing working code
  merely to manufacture a red/green cycle.

## Red/green evidence

- The initial persistence workflow ran **2 tests, 1 failure**, seed 479206: named credential
  save validation worked, but the output sink received opening PCM labeled `:conversation`.
- Added the private-scope assertion to the owning Engine's existing human/text/cache/file
  acceptance. The focused run failed **3/3**, seed 360153, at that same wrong scope.
- The opening playback gate now labels its buffered first frame and subsequent frames private.
  This is the shared boundary for streamed TTS, cached text and files. It does not change
  participant TTS. Gateway recording acceptance already excludes private frames.
- First full opening-file run was **23 tests, 1 failure**, seed 748488: the strengthened shared
  test helper was also used for the agent greeting. Made that call explicitly expect
  `:conversation`; all **23 tests pass**, seed 779962. The persistence flow passed **2/0**,
  seed 916222. No runtime fallback or provider configuration change was needed.
- Extended persistence coverage to cache reuse and tenant/binding isolation, two streamed PCM
  frames, and a credential revoked while the next opening's resolver is paused. The first
  extended run was **4 tests, 1 failure**, seed 779571: revocation correctly stopped its room,
  but an uncorrelated readiness assertion consumed a prior call's notification. Pin that
  assertion to the failed attempt's room ID; do not drain unrelated events or loosen the
  required shutdown outcome.

- The additional tenant exposed a pre-existing ID mismatch: randomly issued tenant keys can
  begin with `_`/`-`, but Engine command validators rejected them. The failure (seed 527483)
  occurred before room creation, independently of opening credentials. Its deterministic fix
  and standalone commit are tracked in [tenant identifier notes](20260915-2050-tenant-identifier-boundary.md).
- The final focused opening workflow passes **4 tests, 0 failures**, seed 369604, with the second
  tenant deliberately using a leading-underscore key. The test proves cache reuse for the same
  binding, misses for a different binding and tenant (even with identical private payloads),
  and closure of a new activation after its opening credential is revoked. Both first and
  subsequent streamed frames arrive private; cached PCM retains the exact concatenated bytes.
- Changed-document relative links and embedded JSON parse successfully. The current opening
  contract now uses inline selections/tenant credentials; historical evidence is labeled.

The standalone identifier checkout passed formatting, warnings-as-errors compilation and strict
Credo. Its umbrella completed **1,503 tests, 1 failure, 30 excluded** (seed 235296, concurrency
four). All 413 Gateway cases passed. The sole failure was the existing live-only STT policy test
not receiving its first audio frame after readiness. That case also failed in isolation. A
temporary state diagnostic observed an open/demanded ingress and passed, which does not prove
a runtime fix; it was removed. The test now explicitly asserts the public room input-admission
state before sending audio, preserving its audio assertion and timeout. The focused case passes
with that stronger precondition. Treat the earlier timing observation as unresolved, and validate
the complete affected file and combined checkpoint before committing.

The final root pass also reproduced the earlier native repeated-transfer listener Morse failure.
The custom two-argument assertion added at the prior checkpoint evaluated a pattern assignment
before producing its diagnostic and raised `MatchError`, hiding the intended decoder state.
Use `match?/2` inside the assertion so failure reports the recorded decoder summary. This changes
only failure reporting; the expected final Morse value and deadline remain identical. The
underlying native timing failure is still unresolved.

The combined umbrella finished **1,507 tests, 2 failures, 30 excluded**, seed 235296,
serialized test cases and module/file preloading. The failures are the Engine partial human
handoff `speech_loss` failed-progress assertion and Gateway's native repeated-transfer listener
Morse `E` timing assertion. All four new database opening cases passed, as did the remaining
applications. Formatting, warnings-as-errors compilation and strict Credo passed before the run.
Do not mark the umbrella or the whole checkpoint 2 exit complete. The tenant identifier
correction is now committed separately as `5a63c40`.

## Checkpoint commit evidence

- The complete opening/speech-policy group passes **43 tests, 0 failures**, seed 504578.
  The encrypted database opening acceptance passes **4 tests, 0 failures**, seed 369604.
- Both full-suite failures pass direct rechecks at seed 235296: **7 partial-handoff cases,
  0 failures, 31 excluded**, and **1 native repeated-transfer case, 0 failures, 67 excluded**.
  These isolated results do not establish a fix for either full-suite observation. The
  native diagnostic now preserves the intended failure summary without a pattern MatchError.
- Formatting, warnings-as-errors compilation, strict Credo and unused-lock checks pass.
  Logs are `tmp/tenant-opening-final-*.log` and `tmp/tenant-opening-recheck-*.log`.
- Commit this opening slice separately from `5a63c40`. Its tenant credential, cache, output-scope
  and human-entry acceptance is covered; full umbrella acceptance remains **1,507 tests,
  2 failures, 30 excluded** and must be resolved before final milestone completion.
  The rest of checkpoint 2 (agent/human transfer, briefing and source recovery with tenant
  credentials) and checkpoints 3–7 remain open. Final independent review remains unavailable
  after the reviewer's usage limit; no final approval is claimed.
