# Implement universal replies

## Initial shared boundary

- Ran bin/setup successfully; no protected provider environment file accessed.
- Read milestone/design and prerequisite contracts. No live calls or deployment.
- Red: registry Session/projection tests failed invalid_configuration and unsupported
  reply protocol. Plan pin failed unsupported_agent_protocol for DeepSeek; modern
  persistence save failed the same error for Google.
- Implemented shared options validation and portable instructed JSON, with existing
  OpenAI Responses schema encoding selected by transport rather than model identity.
  Configuration carries strategy; provider authentication/routing options survive.
- Removed plan identity gate, preserving protocol and idle capability validation.
- Decoupled OpenAI replay from eligibility. Existing cross-model test exposed that
  effective ID alone loses catalog identity; replay now binds both, with compatibility
  for older records without wire_model.
- Green: runtime provider 22 tests (seed 818311), plan/idle 7 (800992), persistence
  23 (710983; 2 exclusions). Google real-adapter HTTP Session and save/publish/prepare
  pass; these fixtures are not live upstream evidence.
- A remains incomplete: bounded correction, full tools after modern blocking
  submission, complete native conversation and live acceptance are pending.
- Astra xhigh design recommendations identify per-attempt token accounting and
  legacy tool-less blocking acknowledgments as contracts to resolve explicitly.
  Implementation review completed after the corrections below; no remaining issues
  in this subcheckpoint. Deferred milestone work is not covered by this signoff.
- Initial misplaced test commands used child-relative paths at umbrella root and
  ran only matching children; focused results above use correct child directories.

## Independent review corrections

GPT-6 Astra xhigh reproduced three implementation issues, each fixed after a
failing test and re-reviewed until clean:

1. Accepted `structured_output` native calls were still rejected by the response
   normalizer. Permanent `req_llm_artifact_test.exs` failed with
   `invalid_provider_response` (seed 482080); removed that name restriction and
   retained calls for ordinary registry authorization. Mixed call/prose and
   truncation coverage retained.
2. `provider_options.tool_outputs` injected a fabricated `function_call_output`
   into the actual OpenAI request even with no corresponding logical history.
   Reviewer captured the HTTP body; permanent options test failed (seed 221759).
   Reject host-owned tool outputs/history at nested and top-level alias surfaces.
3. `context_management` enabled upstream compaction whose opaque records are
   deliberately unsupported by current replay. Reviewer captured the request and
   reproduced `invalid_provider_response` for a completed reply with a compaction
   item. Permanent options test failed (seed 310971); reject both option surfaces.

Final provider directory: 24 tests pass (955510); reviewer independently confirms
24 pass (274871), with no remaining actionable findings. Static root format,
compile warnings-as-errors, strict Credo and unused-dependency checks pass.
Umbrella run seed 608437 is still in progress at this checkpoint; its runtime
child had one 50ms compactor scheduling timeout. The unchanged focused test
passes with the same seed. No clean full umbrella run is claimed yet.

## A — Bounded correction and native tool continuation

- Resolved private `bounded_once_v1` policy before code: pin limits in restartable
  child options, one first-round-only correction under original worker/deadline,
  finite remaining output allowance, explicit reported-output provenance, private
  measured repair context, no compaction/commit or native dispatch from repair.
- Red Session tests: 7 tests / 5 expected failures (414764), including no repair,
  missing output cap and tool-less modern blocking acknowledgments. Nine final
  lifecycle tests cover both attempts' usage, privacy, cancellation, deadlines,
  exhausted/untrusted budgets, no repair after dispatch, restart and tighter reserve.
- Astra's design probe proved Google fills absent usage with zero or reasoning-only
  counts. Added a real-adapter regression: two HTTP requests occurred without a
  trustworthy allowance. Added explicit provenance gating; missing provenance
  disables only correction. Positive OpenAI real-wire repair submits caps 100/90.
- Red accounting test measured only 214 additional units versus 641 required for the
  actual dialogue instructions and schema. The shared conservative counter now
  accounts for both through Dialogue-owned instructions.
- Google real-adapter blocking tool continuation exposed a ReqLLM 1.29.0 buffered
  chat bug: the second wire request used a dummy signature instead of the returned
  thoughtSignature (523544 passes after fix; initial failure 243688). Added exact-source
  patch/manifest and repeatable bootstrap/CI/release preparation. The patch reuses
  ReqLLM's existing object-path signature helper; no direct deps edit is delivered.
- Positive real OpenAI repair first exposed wrong token-option projection
  (118370: provider_unavailable). Preserve the selected transport's token option
  when applying the remaining allowance; real HTTP 100/90 assertions now pass.
- Full runtime child 177 tests pass, 9 exclusions (234505). Initial full root run
  (608437) finished 5471 tests with 2 failures: 50ms compactor scheduling timeout and
  Gateway identity fixture missing required model selection. The former passed
  isolated but received a 500ms test-only budget; the latter was reproduced with
  the typed unsupported_call_plan response and repaired with an explicit fixture
  model. Both ownership contracts remain unchanged.
- Astra implementation review found native token caps overriding runtime caps
  (wire 100 instead of 37), and namespaced provider containers bypassing history
  checks. Permanent tests failed 2/14 (789139); Config now stores ReqLLM-normalized
  options after strict validation, and projection removes nested cap aliases.
  Both flat/namespaced wire cases and option guards pass 14/14 (701406).
- Reviewer also reproduced 21/33 setup fixture failures from the new patch step.
  The fixture now stubs both dependency patchers and asserts compile/failure order;
  34 setup tests pass. The ReqLLM patch preparation test passes fresh/repeat/unknown
  source checks. Astra xhigh re-review is clean (independent correction/wire 15 tests pass,
  seed 257253; setup 34/34 and patch 1/1). Final umbrella verification remains pending.

Final runtime child after option normalization: 178 tests, zero failures, 9 exclusions
(seed 293510). Root format, warnings-as-errors compile, strict Credo and unused
dependency gates pass. No speech/source state-machine implementation changed.

### B: Google native wire subcheckpoint (in progress)

- A's umbrella rerun completed successfully: 5,484 tests, zero failures (the
  runtime child had 177 tests at that run's start; the later focused child run
  included its final 178 tests). No live evidence is implied.
- Added a loopback HTTP fixture capturing buffered and streamed encoded Google
  requests. Initial red: missing responseMimeType. Native object selection now
  probes ReqLLM request preparation offline with schema plus an ordinary tool;
  unsupported combinations retain portable JSON, without rejecting configuration.
- The next red proved ReqLLM raised a requested 100-token cap to 200. A further
  streaming red proved it fabricated a structured_output call from JSON. Expanded
  the checksum-pinned dependency patch to preserve the cap and avoid Google-only
  synthetic tool chunks; object extraction still uses raw response text.
- Fresh and preceding-release patch upgrades pass the shell test. Added raw
  invalid JSON, native signature and unfamiliar-model portable regressions.
- One concurrent test run encountered a loopback request without Content-Length;
  diagnostic added to identify the request. Isolated native wire test passes;
  broader verification and independent review are pending.
- OpenAI's actual Responses buffered/streaming HTTP test passes with the same
  schema, native tools and 100-token cap. Combined Google reproduction seed719580
  passes after the diagnostic change; the missing-length request did not recur.
- Independent review and a permanent new test both reproduced buffered native
  thinking text concatenated with JSON. The dependency text filter now excludes
  thought:true parts. General reasoning replay remains the next B subcheckpoint.
- Runtime child: 182 tests pass (9 excluded) before the final OpenAI/thinking
  regressions were added. Format/compile/strict Credo/unused-dependency pass;
  setup 34 and patch fresh/repeat/upgrade test pass. Full umbrella rerun in progress.
- Review reproduced a second native enhancement regression: configured Google
  Search/URL-context builtins disappeared from object wire output. Permanent
  buffered wire test failed with only custom declarations present; strategy
  selection now inspects canonical options and pins portable JSON when either
  builtin option is configured. Both builtins and custom tools remain encoded.
- Replaced the manual TCP fixture after a second timeout in independent review.
  Bandit (already locked at 1.12.5) is now a direct test-only dependency of the
  runtime child; it owns HTTP parsing and connection lifecycle. Seven combined
  Google/OpenAI wire cases pass against the replacement.
- Re-review proved the SDK also accepts flat builtin option aliases that remain
  outside provider_options after normalization. Extended the permanent wire test
  to nested, flat and namespaced options: flat failed with missing builtins before
  selection checked both locations, and all three forms now pass (seed306434).
- Final Astra xhigh review: no remaining actionable issue in native-wire scope;
  independent 8 tests include the original alias proof plus current Google/OpenAI
  cases, patch preparation/upgrade and whitespace checks pass. Temporary review
  files removed. Final runtime child 185 tests pass (9 excluded). B replay,
  conversation and live acceptance remain open.

### B: Google replay subcheckpoint (in progress)

- Initial real buffered/streamed continuation test failed because runtime replay
  was empty. Added replay dispatch plus a bounded Google record binding private
  reasoning and native call metadata to source text/calls and provider/model IDs.
  Existing OpenAI reasoning/phase tests remain green.
- An ordinary no-tool native dialogue test then failed: ReqLLM object JSON decode
  discarded reasoning_details. Extended the checksum-pinned patch to retain them;
  fresh and both prior released patch states converge through tested upgrades.
- Native continuation wire also dropped supplied call/result IDs. A failing test
  proved missing lookup_1 in functionCall. Google's official content.proto requires
  matching IDs when supplied; patched the encoder to retain both sides. The result
  content remains ReqLLM's existing JSON-string wrapper, not a changed tool result.
- Broader replay adversarial/history tests and independent review remain pending.
- The prior native-wire umbrella run completed: 5,489 tests, zero failures (it
  included runtime 182 before final native-wire additions). Current replay runtime
  child 187 tests pass, 9 excluded. OpenAI replay remains green; independent review
  and current replay umbrella verification are running.
- Self-review found ambiguous atom/string signature aliases could undercount
  private metadata. Permanent bounds test reproduced acceptance of a 70,000-byte
  original signature after normalization selected a short duplicate. Rejecting
  duplicate aliases makes the test pass. Reasoning accumulation then refactored
  to prepend/reverse without changing ordered replay.
- Astra review proved signatures on public text and empty streamed thought Parts
  were lost; preserving them as ordinary reasoning would also move signed Parts.
  Replaced reasoning-only storage with ordered GoogleParts references to canonical
  public bytes/call indices, retaining private text and optional attributes exactly.
  The SDK captures typed raw Parts; runtime normalization removes duplicate public
  text/arguments, and projection reconstructs validated Parts for exact encoding.
- Added native-ID provenance so SDK-generated local dispatch IDs are not inserted
  into originally ID-less signed calls/results. Existing supplied-ID test remains.
- Streaming initially still failed: Google's ResponseBuilder overwrote explicit
  raw-Part records using thinking chunks. Patched it to retain explicit records;
  four focused tests pass, including public signatures, middle thoughts and empty
  carriers in buffered/streamed layouts. Independent re-review is pending.
- Final Astra xhigh signoff: no remaining actionable findings in Google replay
  and pairing scope. Independent final 10 tests pass (seed 990027), following the
  original 12 proof tests and fresh/repeat/both-upgrade patch checks. Permanent
  tests now cover Unicode ordered Parts and absent native IDs in both modes.
  Bounds fixtures use valid Part coverage and valid-small controls so aliases and
  combined-size rejection cannot pass for unrelated missing-layout errors.
- Latest full runtime child before final test expansion: 189 tests pass, 9 excluded;
  final six Google-focused tests and static root gates pass. Current umbrella run
  was started with the earlier 187-test replay slice; completion not yet recorded.
- Final runtime child: 191 tests pass, 9 excluded. Prior replay umbrella run finished
  successfully: 5,494 tests, zero failures. A fresh umbrella run now covers the
  final ordered-Part implementation; live acceptance remains pending.

### Live conversation investigation

- Final ordered-Part root suite completed: 5,498 tests, zero failures. No release
  yet: configured acceptance and remaining integration gates are open.
- Defined the fixed synthetic receptionist scenario before running it in
  `docs/design/universal-replies-live-plan.md`. Added a host-settled Session harness
  with both lookup and hangup declared, pending lookup, trusted later completion,
  idle, cancellation and recovery. Lookup has no external side effect; real room
  Hangup is still separate and pending.
- Initial four configured conversations: OpenAI buffered and streaming pass;
  Google native object reaches model-round limits with unwanted lookup calls.
  Both Google portable comparison cases also fail (listener cue or post-tool
  extra fields). A second portable diagnostic pair proves copying `type` and
  `participant_id` from settled history into replies.
- Clarified the shared system instructions without changing decoder/history/tools.
  Focused tests: 19 pass. Fixed six-case trial still fails all four Google cases;
  both OpenAI cases pass. Native loops on lookup; portable still copies history
  envelope fields. This prompt change alone is not a demonstrated remedy.
- Retained every attempt's step counts, elapsed times, reported usage and failure
  outcomes in `docs/design/universal-replies-live-evidence.json`. Raw synthetic
  diagnostic output stays outside version control. No protected environment file
  was read or changed; all live requests ran through the authorized runner.
- Astra reviewer is tracing actual projected request instructions/encoding for a
  reproducible omission. No production strategy downgrade or permission table
  has been introduced. Further live acceptance remains pending.
- Explicit AUTO did not resolve native Google loops; two additional shared format
  examples did not resolve portable post-tool output. Both experiments retained.
  Reverted all experimental production prompt edits because no remedy was proved.
- Independent real-HTTP review proved instructions survive byte-for-byte through
  all four Google strategy/mode combinations and after native tool results.
  Self-review then found fixture gaps: missing captured Protocol instructions,
  unstructured caller input and delayed pending snapshots. Corrected all three;
  prior runs describe standalone diagnostics, not configured activation evidence.
- Corrected protocol trial: Google portable streaming completed all ten steps;
  buffered portable still failed at asynchronous completion. Native Google still
  loops with or without explicit AUTO. An OpenAI valid lowercase ready reply
  exposed an overly strict semantic assertion; made status/cue matching case
  insensitive without relaxing dialogue validation.
- ExUnit --only includes took precedence over the diagnostic --exclude, so the
  protocol trial ran eight instead of six cases. Recorded all cases; moved the
  selection tag onto just the six intended tests and added tool_choice to future
  metrics. This was a harness selection error, not a hidden successful rerun.
- Astra reproduced a false-positive acceptance harness: one false long sentence,
  a premature completed lookup, arithmetic14 and NOT READY all passed substring
  checks. Tightened command wording/semantic checks and added semantic_outcome
  alongside runtime outcome. Older evidence explicitly distinguishes runtime
  completion from case acceptance. Added missing callback @impl annotations.
  No live run of these tightened checks is claimed yet; local review continues.
- Re-review proved reversed hours could still pass keyword-based long-answer checks.
  Replaced that language grading with a fixed requested three-sentence statement
  over eighty bytes and exact normalized comparison. Reviewer independently
  reconciled all seven evidence runs against retained logs with no omissions.
- Final Astra xhigh harness review: no remaining actionable findings. Permanent
  six-case loopback regression matrix includes a valid complete conversation and
  independent rejection of each proved false-positive class. Six tests pass;
  root strict Credo and whitespace checks pass. Self-review bound the fixture's
  dummy API key to LiveModels' selected environment variable (no ambient key
  dependency). Root umbrella rerun remains in progress; last complete run passed
  5,498 tests. Usage-provenance red tests belong to the next checkpoint.

### Google usage provenance checkpoint

- New raw-HTTP test first failed on buffered known output usage (no correction).
  Negative streaming case also failed: missing/partial output counts authorized
  correction after SDK zero-filling. Final red run: 2 tests, 2 expected failures.
- Preserved reported-input/output flags from raw Google usage metadata across
  buffered chat/object and streaming paths; no change to shared correction policy.
  Explicit candidates plus optional valid reasoning counts are known output;
  missing/inferred/malformed output stays unknown. Reasoning counts consume cap.
- Initial focused repair/wire run: 6 tests pass. Added explicit zero, reasoning and
  malformed controls in all four encoding/mode combinations. Fresh/repeated and
  all three prior-source patch upgrades pass, preserving unknown local edits.
- Defined one fixed two-case portable Google trial after this fix, using the
  reviewed configured protocol and exact semantic fixture; result still pending.
  Native Google strategy selection remains unchanged and its acceptance open.
- Expanded four-way usage matrix passes, including known zero/combined reasoning
  counts and absent/inferred/malformed counter rejection. Independent reviewer
  then proved a multi-event stream could OR an old true flag over a final missing
  count (eight red variants). Added per-event private flags and select the final
  event's reporting facts in Google's response builder. Intermediate partial then
  complete final usage remains eligible; final missing/invalid usage revokes repair.
- Portable live usage trial: both cases failed and are retained. Buffered lookup
  returned invalid_provider_response; streamed lookup gave the expected spoken
  acknowledgment without actually calling the required native tool. No new live
  acceptance is claimed. These failures differ from the earlier usage bug.
- Review additionally proved combined-counter merging could undercount when an
  earlier thinking count7 disappeared or decreased while candidates increased
  from10 to20. Added a Google-only raw-component consistency fence: final candidate
  and thinking counts may not drop below previously reported components to grant
  correction. Normal final20+7 keeps the safe cap73. Permanent usage/replay tests:
  8 pass. Independent final re-review is pending.
- Prior full umbrella harness run completed: 5,498 tests, zero failures. It predates
  the new usage/regression additions; current full rerun will cover those changes.
- Final Astra xhigh usage review is clean: 14 independent adversarial tests pass,
  plus a terminal usage-only SSE positive with candidate10/thinking3 and cap87.
  Fresh/repeat/all prior-source patch upgrades and refusal of unknown edits pass.
  Permanent usage/replay eight tests and all root static gates pass. New full
  umbrella run is in progress. This checkpoint fixes accounting consistency;
  it does not claim the still-failing live conversation acceptance.

### Google encoding capability selection

- Added a failing configuration-boundary test: absent/false schema capability
  metadata previously selected native object solely because SDK preparation worked.
  Red: expected portable, got google_object. Models remain admitted in every case.
- Require affirmative resolved schema metadata plus the existing SDK preparation
  probe for native Google encoding. False/missing metadata pins portable without
  permission gating or dynamic downgrade. Do not infer that metadata proves an
  upstream feature absent or caused prior loops.
- Native wire fixtures explicitly supply schema capability evidence; Google replay
  tests now exercise both native and portable encoders in both response modes.
  The explicit-AUTO diagnostic remains pinned native for future comparisons.
  Initial strategy/wire tests: 7 pass. Broader verification/review pending.
- Final Astra xhigh encoding-selection review is clean. Eleven changed-boundary
  tests pass independently; two additional proofs confirm nil/empty capability
  admission, pinned encoding across tools/AUTO options and later metadata changes.
  Full runtime child: 202 tests pass, 17 live exclusions. Root static gates pass;
  prior usage umbrella run continues. No new live acceptance is claimed here.

### Configured conversation and real Hangup acceptance

- Clarified the synthetic author's native lookup ordering after usage1's premature
  acknowledgment; added bounded SDK finish/status/count diagnostics without raw
  payloads. Configured1: six cases, four pass, two fail. All OpenAI and buffered
  Google cases pass; both streamed Google cases return listener/null only at the
  final after-cancel response. All earlier scenario steps pass, including lookup.
- Extended permanent full-helper loopback control to actual streaming HTTP. Seven
  fixture-contract tests pass, including cancellation/recovery in both modes.
  Defined a six-case follow-up with an explicit speaker resumption request; same
  cancellation timing, output assertion and tools. Result pending.
- New Console live test provisions encrypted temporary credentials, saves/publishes,
  prepares a pinned modern plan, attaches a local text caller and requests actual
  end_call with current_time also available. Google and OpenAI both complete the
  real Hangup action and terminate the room. Two tests pass; no telephone calls,
  external contacts or user specs involved. Metrics retained in evidence JSON.
- Current root usage run exposed STSMCPRoomTest input_format returning not_ready
  while the test expected ready. Independent review is investigating the reproduced
  failure before any green-suite claim. This is outside the modified reply path.
- Explicit-resumption live run: six cases pass, zero failures, covering configured
  and explicit portable Google plus OpenAI in both modes. Together with two real
  published Hangup rooms, this completes B's live scenarios. Prior failures stay
  retained; C–F and deployment remain open. Milestone B's final task is checked.
- Independent root-failure reproduction: 100 unchanged focused MCP cases had six
  failures (both not_ready input format and a stale preparing result). Extracted
  the sibling test's provider-ready trace/state handshake and await it before
  launching the MCP readiness probe. MCP remains gated, preserving the contract;
  no production readiness or speech state machine changed. Focused verification
  and independent repeat/review are running.
- Final Astra xhigh acceptance review is clean. MCP handshake repeat: 100 pass
  after six failures in the unchanged 100; focused real file: 17 pass. Removed
  the newly unused sibling binding. Current full helper: seven pass. Reviewer
  matched all configured1/resume1 sixty-row metrics and both Hangup room records
  to their logs. Root static checks pass; fresh full umbrella run is in progress.

### Direct Chat Completions reasoning preservation

- C audit found replay dispatch discards non-Google/non-OpenAI private reasoning.
  Added real HTTP tests before implementation for DeepSeek/Fireworks buffered and
  streamed native tool continuation. Corrected the Fireworks fixture to use public
  ProviderSelection/model overrides; then all four failed at the outgoing field:
  DeepSeek empty string, Fireworks absent. Red log: chat-reasoning-red.
- Added bounded direct-transport replay with public source/call, provider, model
  and wire-model binding. Streaming SDK emits a duplicate typed reasoning record;
  accept only the exact unsigned duplicate, reject unrecognized private layouts.
  Original guard rejected streamed responses; corrected from observed synthetic
  SDK evidence. Temporary probe logging was removed.
- Fireworks still failed because ReqLLM explicitly strips reasoning_content.
  Current official Fireworks guide requires it for interleaved tool thinking.
  Extended the reproducible cumulative patch to retain that field only, preserving
  other field filtering and all four previous-state upgrades. Installer tests pass.
- Four wire cases now pass, including changed source/call metadata, model/wire
  model/provider, extra envelope fields and over-limit replay rejection. Added a
  focused design record with sources, rejected alternatives and explicit remaining
  router and host-settlement decisions. No C checkbox is checked yet. Astra review
  and broader verification are pending; B's root suite remains running.
- Astra reproduced two failures when reasoning arrived in two SSE chunks: the SDK
  emits one duplicate record per chunk, not one per response. Added that split to
  the permanent wire test; both streamed cases failed before changing the codec.
  Validate the ordered contiguous record sequence and compare joined text exactly.
  Regenerated Fireworks patch fragments with zero context to remove patch-file
  whitespace errors; repeat/fresh/all-upgrade checks and diff check pass.
- Runtime suite before the chunk correction: 207 tests, zero failures (17 live
  exclusions); static root gates pass. B's root run passed all 2,528 CallEngine
  tests but hit a Gateway phone-transfer recovery deadline. Independent review
  is reproducing it; no green umbrella claim or deployment.
- Final Astra xhigh re-review is clean. Independent split-stream/Unicode and
  malformed-detail/bounds checks pass (three tests, seed 949588), including gaps,
  reordering, mismatched text and signed/foreign records. Final runtime suite:
  207 tests, zero failures (17 live exclusions). Root format, warnings-as-errors
  compilation, strict Credo, unused dependencies and patch preparation pass.
  Umbrella run is still active with Gateway failures being investigated separately.

### Gateway verification repair

- B acceptance umbrella run finished: 5,510 tests, two failures, both Gateway;
  all other applications passed. Seed 659133. The Twilio cue-loss case exhausted
  the approved 750 ms recovery budget. Its five focused scenarios, entire 14-test
  harness and 21 cue-loss executions passed independently. Prior outgoing-call
  review notes record the same intermittent timeout; the stalled step is still
  unknown, so no deadline or production change is justified yet.
- Astra proved the WebRTC MCP handoff failure is a test teardown race. It kept the
  real caller request active, induced its worker failure, held the coordinator's
  settlement call with a sys hook, then destroyed the MCP fixture. Room termination
  reproduced the root output_history_unavailable stack. Ordinary repetitions had
  passed, so the deterministic scheduling proof—not those passes—establishes it.
- The test now ends the call and observes its monitored remote_hangup shutdown
  before returning, while ExUnit-supervised dependencies remain available. The
  positive proof left a real continuation pending, closed the call, then destroyed
  the fixture. Four permanent cases pass; independent Astra review is clean with
  12 executions of all four modes and zero failures (seed 659133). No production
  lifecycle or speech-state code changed; no Lean lane needed for this test repair.
- The phone recovery timeout remains unresolved. Full umbrella acceptance must be
  rerun after the ongoing router checkpoint and this repair; no all-green claim.

### Router replay and remaining-provider evidence

- Initial router wire matrix: twelve cases, ten failures. Both routers lost raw
  details on continuation; streamed responses also reported the configured model
  instead of the actual returned model. Added an exact-source SDK patch for raw
  maps and explicit consistent model provenance. Zenmux also needed raw detail
  encoding; generic encoder previously discarded its own buffered raw maps.
- Astra design review rejected response-only origin checks: native fallback can
  already have sent an old blob to a different model. Record/model-pin all retained
  replay, remove alternate-model routing and disable Zenmux fallback with string
  false before HTTP. Preserve other configuration and original ordinary routing.
  Conflicting origins or changed source/options fail before HTTP. The initial
  mismatch-rejection test was revised to this documented affinity behavior; four
  contradictory later-response cases failed before adding their admission guard.
- Do not invent provider slug mappings or a universal endpoint-identity gate.
  Review found documented cross-platform compatibility for some signatures and
  no general same-model incompatibility reproduction. Model affinity remains
  necessary; additional provider compatibility constraints need evidence.
- Review proved malformed private fields were silently dropped (four cases),
  whitespace origins admitted tools (four cases), and buffered textual reasoning
  could overwrite/invent native calls (four permanent cases). Added each proof to
  the wire suite before fixing it. Guards retain invalid-present markers, validate
  known payload types and require nonblank origins. Removed buffered reattachment
  that could overwrite markers in mixed-field responses. Modern native-only SDK
  flag disables textual tool parsing while preserving legacy defaults.
- Focused final matrix: 32 tests pass. Patch fresh/repeat/all-five-upgrade checks
  pass. Registry coverage test failed before adding the shared six-provider list;
  eight helper cases now pass. Full runtime before final guard additions: 223
  tests pass, 17 live exclusions. Final independent review/static checks pending.
- Fixed identity diagnostic ran four cases: both OpenRouter requests completed;
  both Zenmux cases failed before HTTP because the child lacked ZENMUX_API_KEY.
  No protected environment file was accessed. User explicitly directed skipping
  Zenmux for now; recorded live-only deferral while retaining deterministic tests.
- Fixed remaining1 conversation run: six cases, four pass, two fail. DeepSeek
  streaming, Fireworks streaming, and OpenRouter in both modes pass all ten steps.
  Fireworks buffered added type/participant_id on unrelated arithmetic and did not
  correct despite finite output usage; provenance review is investigating. DeepSeek
  buffered returned listener/null at the requested cue. All rows/failures retained
  in live evidence; no checkbox claims these failures as acceptance.
- Final shape review proved valid null/absent reasoning.text carriers were being
  rejected. Added a null carrier to the permanent exact-sequence test: four red
  cases before allowing nullable text/signature; malformed present types still
  fail. Independent final review is clean: 54 adversarial checks, 16 final controls,
  two legacy cases, all five patch upgrades, and whitespace check pass. Final
  runtime: 240 tests, zero failures (25 excluded). Root static gates pass.
- Checked C tasks 1 and 4 based on reviewed transport audit and registry/matrix
  evidence. C lifecycle and remaining enabled live acceptance stay open; milestone
  index stays unchecked. The approved Zenmux deferral is explicit, not a pass.

### Buffered Chat Completions usage provenance

The retained remaining1 Fireworks buffered failure exposed missing output-count
provenance. Independent Astra local-HTTP proofs also found malformed nested
reasoning usage could incorrectly authorize correction. Converted both matrices
into permanent public Session tests across DeepSeek, Fireworks, OpenRouter and
Zenmux, buffered and streamed. Pin a known context budget in fixtures to isolate
usage from Zenmux's absent catalog context limit. Red: 96 cases, 12 failures;
reported positive/zero output rejected and malformed reasoning accepted only in
buffered responses. No live calls or protected environment reads for this proof.

The SDK buffered decoder now merges just normalized reporting/completeness facts
into parsed usage, preserving provider fields. Strict DialogueRepair is unchanged.
Green: all 96 cases pass, including missing, malformed, inferred and forged usage
controls. Cumulative patch preparation passes fresh/repeat, all six prior states
and refusal of unknown local edits. Independent Astra checkpoint review is clean: 104 focused tests and 72 additional
adversarial cases pass, including explicit null/zero, integer-string counts,
floats/booleans, negative reasoning, invalid cached counts and forged provenance.
Root format, compile, Credo and unused-dependency checks pass. Full umbrella and
fixed remaining2 live conversations are still running; no final gate claimed.

The fixed remaining2 live run finished: six conversations, three failures.
OpenRouter both modes and DeepSeek buffered passed; the latter demonstrates actual
bounded correction with reported usage. Both Fireworks failures have explicit
`length` completion and zero public text at the 2,048-token cap. DeepSeek streaming
emitted host-envelope fields after lookup, so the post-tool no-correction rule
correctly rejected it. Retained all evidence; live acceptance stays open.

### Reasoning-cap live follow-up

The explicit Fireworks `length` failures motivate increasing the common live
fixture cap from 2,048 to 8,192 and recording it in step evidence. This is bounded
test configuration, not a production retry/schema-policy change. Defined exactly
two six-case repetitions before running them, with unchanged prompts/assertions
and all failed attempts retained. No initial red test is needed for this
configuration-only change; the full local helper tests verify its path.

Both planned higher-cap repetitions finished with four failures each. Fireworks
never reached HTTP: ReqLLM rejects/caps buffered max_tokens above 4,096, and strict
public selection rejects the resulting warning (streaming selection traverses
that same chat validation). DeepSeek both modes returned invalid post-tool host
envelopes; OpenRouter both modes passed. Added offline all-six live-selection
budget preflight: 9 tests, one expected failure at 8,192. Corrected the common
fixture cap to 4,096. Retained both entire attempts; no further stochastic reruns
until the lifecycle fix and a new fixed plan.

The corrected cap preflight and full helper suite pass: nine tests, zero failures.
Astra's D coverage audit found existing protocol snapshot, transfer/restart,
legacy, editor edit-retention and authorized catalog coverage; avoid duplicating
those harnesses. Remaining focused gaps: modern other-four Persistence and real
provider Console authoring, invalid modern options/credentials without revision
changes or inference, malformed known-version bundles, configured-sample snapshot
assertion, stale model-eligibility error guidance, and rendered editor/call
acceptance. Audit checks passed Calls/errors 19, Persistence/codec 6 and frontend
editor/catalog/errors 41. Source locations and full findings remain in review
messages; these observations do not check off D acceptance.
Astra cap/evidence review is clean: independent helper 9/0; every historical run
is preserved, all 60 new emitted rows retain the actual attempted 8,192 cap, and
all four Fireworks offline rejections are explicitly recorded. Corrected 4,096
configuration passes all six preflight selections. No production change.

### Full-delivery unsigned reasoning lifecycle

Independent Astra public Session HTTP reproduction found direct unsigned final
reasoning absent from subsequent tool-enabled requests even after full delivery.
DeepSeek's primary thinking-mode contract explicitly requires preceding reasoning
when tools are declared. Permanent DeepSeek/Fireworks buffered/streamed fixtures
failed four full-delivery cases out of twenty; partial, edited, mode-changed and
nil-delivery controls passed. The private pending candidate now validates original
source/model, retains bounded replay plus a mode/text digest, and rebinds only
on exact full host settlement. Public Result/events and generated/legacy history
remain unchanged; signed/opaque shapes are not candidates. Design and rejected
alternatives are recorded in the transport investigation.

Focused green: 23 cases, including accepted native-exchange cancellation/failure
recovery and protected-tail compaction without private summarizer input. No Lean
lane is indicated: this changes runtime history settlement metadata, not source
cutover or speech-state transitions. Independent final review and runtime/static
verification remain in progress; C2 is not yet checked off.

Final lifecycle review is clean. Adopted seven adversarial controls covering
source/model/provider tampering, malformed/oversized shapes, Unicode, private
Result/events/Inspect, stale/invalid/duplicate settlements, admission fencing,
fixed greetings, cancellation/failure and exact-once retained reasoning recovery.
All seven pass; focused preceding 23 pass; runtime child 360/0. Root static gates
and unused dependencies pass. Checked C2: milestone 11/24 (46%). The concurrent
umbrella run has now passed Gateway 890/0, including both prior failure sites;
it predates this lifecycle change and is not final-release verification.

### Modern authoring and publication compatibility coverage

Extended the existing A Google/OpenAI public authoring regression to all six
installed integrations in Persistence: save/publish/prepare retains the modern
snapshot, configured selection and credential privacy. Invalid option types and
missing credentials do not create rows. Console's actual browser-authenticated
JSON authoring boundary now saves/publishes all six real provider selections;
invalid updates retain source, latest revision and published pointer. Both lanes
observe SDK request-start telemetry and reject inference during authoring.

Added malformed known-version publication bundles (bad prompt hash, missing
prompt, extra bundle/prompt fields) through Calls preparation and activation.
Configured-sample resumption asserts the existing modern snapshot is preserved;
explicit legacy sample creation remains intentional compatibility coverage.
These are coverage additions for behavior already implemented, not new runtime
changes; the earlier A regressions supplied the failing eligibility evidence.
Focused checks: Persistence28/0 (2 exclusions), Console24/0, Calls17/0,
activation5/0, sample resumption6/0. Independent review is pending. Rendered editor
and transcript evidence, stale guidance and live acceptance remain outstanding.

The concurrent umbrella run completed successfully: 5,654 tests, zero failures,
seed844757; root command exited0. Application counts: Identity101, Providers222,
MCP35, Runtime336, CallEngine2528, Calls392, Gateway890, Artifacts20,
Persistence551, Console579. Both earlier Gateway failure sites passed. This run
started before the lifecycle implementation (Runtime336), while later app tests
included the new authoring coverage, so a fresh final umbrella remains required
once remaining changes settle. Local evidence log: `vxpipe-universal-c-root.log`.

Astra authoring checkpoint review is clean: 84 independent tests pass, two
excluded. Existing actual compaction prompt test plus activation publication
pinning closes the apparent custom-summary gap. Checked D1/D2; milestone13/24
(54%). No UI/rendered or live acceptance claim is made by these backend tests.
