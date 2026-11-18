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
