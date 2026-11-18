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
