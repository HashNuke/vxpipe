# Direct LLM services

## Checkpoint scope

- Add DeepSeek, OpenRouter and Fireworks to the fixed provider registry, with
  exact single-key credentials. DeepSeek and OpenRouter expose read-only probes;
  Fireworks has no verified authentication-only probe, so its form permits Save
  and explains why credential testing is unavailable.
- Keep LLM execution in ReqLLM. Validate model IDs and a closed public option
  set, use fixed upstream endpoints and reject public keys, URLs or HTTP hooks.
  DeepSeek's current Flash alias and OpenAI Luna postdate the installed LLMDB
  snapshot; reviewed internal metadata preserves their wire identities. Luna
  selects Responses and its output-token bound. Do not invent current pricing.
- New direct providers default to 4096 output tokens. Explicit caller limits
  remain authoritative. Catalog-wide defaults had failed Fireworks validation.
- Call startup resolves the selected tenant credential through the existing
  platform fallback contract. Console includes installed service labels, API-key
  forms, parsing, demo readiness and exact published model/credential selection.
- No database migration or gateway provider dispatch is introduced.

## Verification and decisions

- Credential, selection, scope, model-default and form regressions were written
  before their behavior changes. Demo acceptance first failed on the older
  Google/Zenmux readiness restriction; Fireworks's default-bound regression also
  failed before adding the bounded default.
- Provider selection: 8/8. Persisted Console demo acceptance: 7/7, including
  platform inheritance and tenant overrides. Credential form: 16/16.
- Frontend check and lint pass; the full frontend suite passes 202 tests.
- Rendered Chrome inspection covered platform DeepSeek at 1440x1000 and tenant
  Fireworks/OpenRouter at 390x844. These were synthetic Storybook states, not
  browser proof of persistence. Backend tests own persisted acceptance.
- The impeccable finishing review returned ship with no material fixes for the
  narrow catalog/form extension. Existing design language remains authoritative.
- Individually selected live DeepSeek, OpenRouter and Fireworks contracts each
  passed a tool call, continuation and usage check, capped at 256 tokens per
  request. OpenAI's Responses contract passed separately. Those opt-in tests and
  their shared catalog are committed in the following live-lane checkpoint.
- Format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
  Full umbrella acceptance remains under repair; these focused checks do not
  imply that the whole provider milestone or new speech support is complete.

Keep the private live credential file untouched and preserve the unrelated
documentation-site configuration change in the worktree.
