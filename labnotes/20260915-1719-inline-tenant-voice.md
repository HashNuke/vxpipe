# Inline tenant voice

## Checkpoint scope

Continue checkpoint 1 after encrypted provisioning and shared platform storage. Introduce inline
provider/model selections, hard tenant credential checks on save/publish/prepare, private runtime
resolution, and a runnable synthetic Google/Deepgram voice flow. Remove profile/global credential
configuration and the speech-profile runtime switch. Keep the full milestone open until all exits
pass; no compatibility profile path is intended.

## Initial red evidence and review

- Parser/compiler test first: 3 tests, 2 expected failures, seed 267166. Current parser rejects
  schema `20260915.01`; a negative case also checked that errors point at the capability instead
  of failing incidentally on the schema. Persistence workflow first: 2 tests, 2 expected failures,
  seed 167785; the inline save is rejected before the workflow can proceed.
- The persistence workflow currently reaches provision/save/publish/prepare/join-token claim.
  Actual room activation and synthetic audio exchange still need to be added and verified.
- Independent GPT 6 Astra xhigh source review identified hard-error separation from draft support
  errors, fresh publication/preparation checks, explicit credential-source propagation through
  filtered runtime options, and a concurrency check at persistence writes. Resolve credentials
  inside existing preparation workers, outside room callbacks.
- Installed ReqLLM can obtain a provider endpoint from application settings even when an API key
  is explicit. Translation must pin the code-owned endpoint and Google header authentication;
  public option maps cannot supply endpoints, headers, credentials or transport code.
- Serialized plans contain all fields, so inspect actual stored terms/bytes, not only redacted
  Inspect output. Reject old schema/profile plans at activation. Later STT process creation must
  obtain fresh credentials instead of reusing entry runtime credentials indefinitely.

## Implementation progress

- Added `ProviderSelection` in Agent Runtime and `CapabilityCatalog` in Engine. Parser/compiler
  accepts schema `20260915.01` with actual provider strings and whole-selection overrides;
  removed profile registry resolution and the selection's profile field. Engine owns a neutral
  private credential snapshot/source; Calls bridges to tenant repository resolution.
- Added hard save, publication and preparation checks. After inline parsing went green, the
  wrong-tenant workflow failed because it incorrectly saved successfully (seed 910246).
  Added revoke-before-publish/prepare tests: 4 tests, 3 expected failures (seed 696852), then
  all 4 passed (seed 412465). Source resolution had an undefined-module red failure, then
  all 5 persistence cases passed (seed 945127).
- Replaced `AgentModelProfile` with `AgentModel`: hosted Google uses explicit tenant auth and
  translated public options. Speech constructors similarly stop merging global private options.
  Propagated the credential source through room supervisor/startup and Gateway option filtering.
  Usage/cache identities derive from tenant and the complete public selection.
- Constructor test red: 3 tests, 1 failure (seed 157122). The first implementation also rejected
  its own `on_unsupported` option because provider Config owns that policy; translated options
  now omit that flag until Config applies it. All 3 constructor tests then passed (seed 969396).
- Added a PostgreSQL-backed synthetic voice test through actual Google ReqLLM streaming and
  Deepgram speech adapters. It first failed when runtime option filtering dropped the source
  (seed 506708). After propagation, STT succeeded but model generation used non-streaming and
  bypassed the synthetic streaming interceptor. That failed attempt used only a synthetic key;
  it reached the normal request path, so do not claim every attempt was request-free.
- Both probed Google model records omitted `capabilities.streaming.text`, making the installed
  automatic helper return false. Added a failing explicit-streaming translation assertion
  (seed 531052), then selected the documented Google streaming text protocol in the adapter.
  Official source: https://ai.google.dev/api/generate-content#method:-models.streamgeneratecontent.
  The synthetic test now checks that precondition before startup. The successful request was
  captured before redirection to a supervised localhost HTTP fixture and asserted the expected
  endpoint/header credential, received a streamed reply, and delivered Deepgram speech output.
  Persistence workflow: **6 tests, 0 failures**, seed 140306.
- Added red tests for decoded selection extra/private fields and STT state inspection:
  5 tests, 2 expected failures (seed 583821). Added current-plan selection validation and an
  Inspect projection for STT state. Combined Engine focused cases: **8 tests, 0 failures**,
  seed 958255. Scoped formatting covered 31 changed Elixir files.

## Open work and review availability

- The requested GPT 6 Astra xhigh reviewer delivered the initial source review. Its subsequent
  transport investigation failed with a usage-limit error. Final independent implementation
  review has not happened; local implementation can continue while that gate remains open.
- Source inspection found another actual disclosure boundary: installed WebSockex's
  `execute_telemetry` includes its complete connection, including extra authorization headers.
  The new STT Inspect projection only protects routine state output. The transport work below
  closes the observed WebSockex disclosure; independent review remains required.
- Concurrent save/revoke ordering and later STT creation were open after initial preflight work;
  the changes below address those paths. Keep transfer/carrier lifecycle acceptance open.
- The development/trusted-input/Console cutover and fixture migration are recorded below.
  The full umbrella is not yet a verified usable checkpoint; keep these changes uncommitted
  until the vertical slice and its gates are coherent.

## Speech transport regression and replacement

- Local STT/TTS wire tests first reproduced the actual WebSockex authorization telemetry leak:
  **2 tests, 2 expected failures**, seed 373684. Both successful wire exchanges contained the
  synthetic key in emitted connection metadata.
- Replaced Engine's WebSockex client with Mint and Mint.WebSocket, both already locked. Engine
  now declares its direct use; WebSockex remains transitively required by ReqLLM. Connection
  setup has bounded connect/upgrade deadlines, no logging, safe errors, no redirect/reconnect,
  and no retained request headers. Existing STT callback unit checks still pass.
- Close-during-output regression first failed (**7 tests, 1 failure**, seed 613074). Moved TTS
  acknowledgement to the socket process state with the existing 15-second deadline; active-once
  input is held until the owning output acknowledgement. Close and keepalive stay responsive.
- A deterministic fixture sends the upgrade and initial provider frame in one write. Initial
  handoff failed (**9 tests, 1 failure**, seed 820508), then passed after preserving the upgrade
  body's frame. Combined protocol/callback cases: **11 tests, 0 failures**, seed 35220.
- A coalesced pending-payload inspection test failed as expected, seed 932304. Added a redacted
  Inspect projection in addition to crash `format_status` redaction. An earlier version of this
  check was timing-dependent because the fixture sent separate frames; it was replaced with the
  deterministic coalesced fixture before implementing the projection.
- Broader provider suite: **47 tests, 1 failure**, seed 415587. The failure was the old profile
  input in the Morse room round-trip test. Migrated that test to inline Morse/fixture selections;
  focused round-trip then passed (**1 test, 0 failures**, seed 876703). Other old profile fixtures
  remain outside this provider directory; the umbrella cutover is not complete.

## Fresh speech creation and transactional credential gates

- Added a real database test revoking Deepgram after initial room preparation and before caller
  attachment. It failed by returning a successful attachment (**7 tests, 1 failure**, seed 536578).
  Every new planned STT process now resolves the selected binding; established processes retain
  their snapshot. The workflow then passed (**7 tests, 0 failures**, seed 337629).
- Added owned-worker and cancellation tests before `ConnectionSpeechPreparation` (**6 tests,
  2 failures**, seed 779616). The first async-nolink implementation passed deadline/ownership
  checks but a new owner-exit test showed it left lookup running (seed 627025). Use a linked task
  under the existing ReadinessTaskSupervisor; all **7 tests pass**, seed 807681. The caller's
  deadline is capped at 5 seconds. Deadline expiry discards even a raced late result.
- The new synthetic voice/network tests are explicitly tagged integration, and Persistence now
  excludes that lane by default, matching Engine. Focused commands use `--include integration`.
- A controlled preflight/revocation interleaving failed by inserting a revision after revocation;
  the transaction callback was initially undefined (**7 tests, 2 expected failures**, seed 156614).
  Added the neutral `with_active` repository contract: lock bindings in deterministic order,
  decrypt/validate, perform only the final database write in the same Repo transaction, and
  rollback any returned error. No secret is passed to the operation callback.
- Save/publication and web prepared-call insertion now use that boundary; provider/audio work
  stays outside its locks. Added preparation interleaving coverage. Inline workflow plus existing
  provider credential store tests: **18 tests, 0 failures**, seed 568346.
- A two-connection PostgreSQL check reached the expected blocked revocation, but its first writer
  callback included complete model validation and exceeded the 1-second result assertion (seed
  424648). The fixture now prebuilds the revision and performs only its store write under the lock,
  matching the intended transaction boundary. The two-connection check then passed (**1 test,
  0 failures**, seed 585147): a competing revoke times out while the write holds the binding;
  revocation succeeds after commit and blocks publication. This integration fixture creates only
  its own tenant data in the test database and removes it on exit. Scoped formatting covered
  49 changed Elixir files before the combined verification pass.


## Runtime and stable Console tenant cutover

- Combined speech transport/provider and inline Engine tests passed **58 tests, 0 failures**,
  seed 147451, including the explicit integration lane. No live provider keys were supplied.
- Removed global Google/Deepgram key reads, boot-time requirements, the speech-profile reader
  and both branches, and the old development model-fixture switch. Dev/sample definitions
  select upstream providers inline. Negative runtime tests first failed **2/2**, seed 826944;
  runtime plus shared-storage checks passed **7/0**, seed 576702.
- TrustedCall accepts only its declared options and rejects the retired profile registry.
  Its two new checks first failed, seed 54521, then passed **2/0**, seed 770976.
- Console setup requires `VXPIPE_DEV_TENANT`, reuses that tenant, saves/publishes before issuing
  a server-held call key, and never bootstraps tenants. Its changed tests first failed **6/5**,
  seed 276648. The combined sample, endpoint, provider-runtime and storage checks passed
  **24/0**, seed 633006, including the absent-selector/selected-tenant configuration cases.
- A disposable development database with randomly generated platform encryption and synthetic
  tenant Google/Deepgram keys served Console on an owned listener. Inspected Chrome screenshots
  at 1440×960 and 390×844: heading, copy and action rendered without clipping. Preparing a call
  through `/sample/calls` returned 201, only public locators plus join token, and no synthetic
  provider marker. Restarting the BEAM reused the tenant; DB counts progressed from 1 tenant,
  2 credentials, 1 definition and 0 calls to 1/2/2/2 after preparations across restart. Browser
  did not join or contact live providers. Closed the owned browser/listener and dropped the DB.
  Screenshots and orchestration remain ignored under `tmp/`.

## Fixture and documentation migration

- Calls fixtures initially failed on their retired schema (**24 tests, 23 failures**, seed 208800).
  Replaced static profile inputs with inline fixture/Morse selections, removed registry maps,
  and migrated explicit fixture adapter injection. Calls then passed **24/0**, seed 17584.
- Updated parser/plan tests to the new typed fields and schema. The first compiler pass found one
  remaining test-side profile lookup (**84/1**, seed 226058); the corrected parser/startup/readiness
  pass passed **91/0**, seed 421718. Unsupported profile strings remain explicit negative cases.
- Migrated dynamic model, opening, transfer and carrier fixture builders. Speech lifecycle tests
  use a test-only credential source with synthetic payloads and their existing local transports;
  the tenant authorization tests retain exact tenant/binding maps and real store integration.
- Six major room suites ran **120 tests, 4 failures**, seed 364227. The failures were stale
  expected provider/usage identity labels. Updated these to public provider and selection hash;
  the four failed cases then passed, seed recorded in `tmp/inline-engine-room-recheck.log`.
- Updated development, Elixir quick-start, credential/control-plane and Console walkthroughs,
  plus the current JSON example. The old Morse milestone evidence is explicitly historical.
  Full Engine child verification is now running. Independent review and root gates remain open.


## Commit cadence correction and completion pass

- The user requested immediate small, tested commits after too much work accumulated. Extracted
  three independent checkpoints and verified each against its actual committed parent in a
  disposable checkout, then committed: `8dc1cbe` speech transport privacy (25 focused tests),
  `5203ca0` Google translation (93 Agent Runtime tests), and `e14e82d` stable Console tenant
  (16 sample/endpoint tests). Each passed root formatting, compile and strict Credo; transport
  also passed the unused-dependency check. Their dedicated labnotes record exact evidence.
- Removed that clean verification checkout and its owned build/dependency copies. No user
  worktree changes were stashed, reset or moved into those commits.
- The Engine child suite reached **664 tests, 1 failure, 12 excluded**; one remaining remote-MCP
  fixture still passed a TTS profile through `Map.put`. Replaced it with the same explicit
  Deepgram selection. Its focused check passed **1/0, 3 excluded**. This was a fixture error,
  not a provider/runtime failure.
- Root formatting, warnings-as-errors compilation and strict Credo passed on the remaining
  checkpoint. The full umbrella test pass is running. Test compilation found three unused
  provider aliases in migrated Gateway helpers; removed them mechanically.
- The first full umbrella run used seed 230554, preloading, one compiler file at a time and
  four test cases. It ran **1,487 tests, 1 failure, 30 excluded**. The sole failure was the native
  repeated-AI-transfer listener Morse assertion (`:invalid_timing` while expecting `E`), also
  observed before this schema change. Rerunning that exact case from Gateway with the same
  seed passed **1/0, 67 excluded**. Source inspection did not establish the cause; assertions,
  audio timing and deadlines were not changed to obtain that pass.
- Rechecked the Persistence tenant-voice/store/two-connection transaction files with
  `--include integration`: **19 tests, 0 failures**, seed 171666. Formatting, warnings-as-errors
  compilation in development and test, and strict Credo pass. A full umbrella rerun at seed
  230554 is in progress; the initial run stopped before the unused-dependency gate.
- That rerun again had **1,487 tests, 1 failure, 30 excluded**. The repeated-AI Morse case passed;
  this time the five-participant changing-listener test observed no ordered cue/conversation
  audio on one peer. Its isolated check with the same seed, preloading and one compiler file
  at a time passed **1/0, 67 excluded**. The failure trace did not establish a cause. No source,
  assertion, audio pacing or timeout change was made between these checks. The next umbrella
  run uses seed 235296, the previously recorded green baseline order. Neither isolated pass
  is evidence that an intermittent media problem is fixed.
- Reviewed the staged checkpoint: exactly 111 source, test, sample, documentation and labnote
  paths. All are part of the shared schema/consumer cutover after the three independent commits.
  Checked 202 relative documentation targets with no missing files, parsed the current JSON
  example, and verified the visible sample exists with no dotted sample. `git diff --cached
  --check` passes. Final independent review remains unavailable after the reviewer's usage limit.
- The seed-235296 umbrella run also finished **1,487 tests, 1 failure, 30 excluded**. Both earlier
  audio cases passed, but `after_speech_adoption` timed out waiting for destination progress.
  The case passed alone (**1/0, 67 excluded**), then source review identified the actual recipient
  bug: promotion clears the transfer marker used to select the destination. A new focused test
  reproduced that bug deterministically. Committed its fix separately as `d2b4785`, with test,
  milestone evidence and [labnotes](20260915-1947-handoff-progress-recipient.md). The standalone
  unused-dependency check also passed after the failed umbrella run.
- The progress fix was verified against its committed parent in an isolated checkout, preserving
  the 111 staged inline paths. The combined root gates are running again after this production
  fix. Keep the unrelated Morse/listener audio observations open; this fix addresses destination
  event delivery and does not establish a cause for those audio failures.
- After `d2b4785`, the umbrella ran **1,488 tests, 1 failure, 30 excluded**, seed 235296.
  The adoption-progress case and both earlier audio cases passed. The remaining failure was
  `private WebRTC media stays gated and cleans up after room_output loss`: the connection
  monitor reported `:noproc`, while the test expected `:shutdown` (native test line 2814).
  This means the connection had already exited when monitoring began. Its earlier exit is
  unexplained; do not weaken the exit assertion or call this a verified cleanup fix. The
  test installs its monitor after `verify_private_candidate/7`, so trace that preparation and
  collector cleanup boundary before another blanket rerun.
- Every other application passed. Root formatting, warnings-as-errors compilation, strict
  Credo and the unused-dependency check pass. The 111-path inline schema checkpoint remains
  staged and uncommitted because full umbrella acceptance is still red. Four separate tested
  checkpoints have been committed in response to the user's commit-cadence correction.

## Final boundary review

- The continuation strengthened native cleanup monitoring before private preparation. Three
  focused cleanup cases and the full native handoff file (**67 tests, 0 failures, 1 excluded**,
  seed 235296) pass. See [private cleanup evidence](20260915-2003-private-cleanup-race.md).
  That result does not prove the earlier premature exit or audio failures are fixed.
- Local review found that the explicit fixture configuration could point at the hosted ReqLLM
  adapter and thereby construct a model outside tenant credential resolution. A new regression
  failed as expected (**4 tests, 1 failure**, seed 181399), returning a configured hosted model
  for the credential-free fixture. Fixture selection now rejects that adapter whether its
  options contain an explicit key or would permit ambient discovery. No request was sent by
  this constructor test; only a synthetic marker was supplied.
- The model constructor, inline activation and inline parser suites now pass **14 tests,
  0 failures**, seed 130719. The root completion gates are running after that boundary fix
  and the stronger native cleanup assertions.

- The next full umbrella run completed **1,489 tests, 1 failure, 30 excluded**, seed 235296.
  The failure returned to the native repeated-transfer listener's Morse `E` flush
  (`:invalid_timing`); the strengthened cleanup cases passed. Formatting, warnings-as-errors
  compilation and strict Credo passed. Added decoder-state context to that assertion without
  changing its signal checks, deadline or expected result, then started the same umbrella
  order to capture useful evidence if it recurs. The earlier isolated native pass does not
  establish that this intermittent audio observation is resolved.
- Final source/path review accounts for exactly 112 checkpoint paths and no unrelated changes.
  Changed-document relative links resolve, both diff whitespace checks pass, the deleted config
  app remains absent, and retired speech/model environment names occur only in the intentional
  negative configuration tests under the reviewed runtime paths.

## Verified checkpoint closeout

- All five root gates pass after the fixture-authentication fix and stronger native assertions:
  `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296`, and
  `mix deps.unlock --check-unused`. The final umbrella result is **1,489 tests, 0 failures,
  30 excluded**, including **666 Engine** and **413 Gateway** tests. Compilation evidence is
  in `tmp/inline-closeout-compile.log`; final remaining gates are in `tmp/inline-audio-diagnostic-*.log`.
- The native Morse failure did not recur, so the added decoder-state diagnostic was not exercised
  by a failure. Do not infer that its underlying cause, or the earlier cleanup observation, is
  fixed. No audio expectation, timeout or integration exclusion was changed to obtain this pass.
- Keep the 19 passing explicit database/integration acceptance tests and disposable-browser
  provisioned-tenant restart evidence above. This checkpoint does not claim live provider acceptance.
- Mark checkpoint 1's delivered tasks verified and keep the entire milestone, checkpoints 2–7
  (apart from already delivered shared storage), and final independent implementation review open.
  The reviewer usage limit still prevents that final review; the earlier source review is separate.
- Commit the reviewed shared schema/runtime cutover with its implementation, migrated fixtures,
  documentation and both labnotes. Subsequent call-flow work starts from this usable checkpoint.
