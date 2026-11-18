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
