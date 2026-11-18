# Universal agent replies investigation

## Scope and findings

- User requests investigation and a milestone, not runtime implementation: every LLM integration must support the shared response contract without a provider/model allowlist.
- Inspected Dialogue, RequestRunner, SessionConfiguration, AgentProtocol, ReqLLM DialogueProfile/RequestProjection/ResponseNormalizer/OpenAIReplay, production provider manifests and existing live test lanes.
- All six installed production LLM manifests (Google AI Studio, OpenAI, DeepSeek, Fireworks, OpenRouter, Zenmux) select the common ReqLLM adapter. Shared dialogue parsing and final-output buffering already exist.
- Identity gating exists in plan compilation and Session/request configuration. RequestProjection additionally sends OpenAI-shaped schema options; OpenAI replay restore depends on the same compatibility predicate. Removing a single predicate would not complete support.
- Lockfile versions: ReqLLM 1.29.0, LLMDB 2026.10.6. Inspected installed Google schema/tool request handling, including gemini-3.5-flash-lite handling; dependency feature presence is not live Vxpipe acceptance.
- Read the completed structured-message milestone/design and historical failed Google candidates, including the invalid tool-removal acceptance shortcut and later native OpenAI reasoning replay corrections. Existing evidence remains historical rather than rewritten as universal acceptance.
- Consulted current primary Google, OpenAI, DeepSeek, Fireworks, OpenRouter and Zenmux documentation; links and bounded conclusions are recorded in the durable design. No web page or dependency capability was treated as proof of successful Vxpipe calls.

## Plan and design review

- Added durable universal-reply design and a six-checkpoint milestone: shared portable contract; Google/OpenAI parity; other installed integrations; authoring/compatibility; common evidence; release.
- Proposed native schema/JSON modes as optional transport enhancements, with shared instructed/validated JSON as the portable path. Every path retains the strict common decoder and full native business tools.
- Proposed bounded correction only before any dispatched tools or speech, within the original budget/deadline. Recovery/pinning details are explicit A tasks, not completed or implied user approval of every implementation detail.
- Local specification review separately checks ownership, side-effect safety, replay, router changes, registry completeness, historical compatibility, save/publish parity, live evidence and dependency ordering. No new independent review agent was requested or used.
- Inserted the unchecked milestone after structured messages and the completed draft/publication prerequisite, before remaining voice behavior. Moved that completed prerequisite ahead of its consumer and corrected stale index totals to the actual 52 checked and 15 unchecked entries. Added policy-supersession notices to the prior design and milestone without unchecking completed historical work.
- No implementation, dependency, credentials or production changes; no live inference. Documentation-only verification is proportionate rather than another application test run.

## Verification

- Relative links in new documents resolve; all 67 indexed milestone targets exist and numbering is contiguous. Actual index status is 52 complete / 15 incomplete.
- All five direct prerequisites precede the new entry. Six checkpoints contain 24 unchecked implementation tasks; no implementation checkbox was marked complete.
- Local design review is recorded separately in the milestone. The first document check found stale historical index totals; corrected them to the actual checklist rather than carrying the mismatch forward.
- `git diff --check` passes. No application tests or deployment are needed for this documentation-only checkpoint.
