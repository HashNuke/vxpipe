# Barge classifier integration research

## Scope and constraints

- User requested research and a proposal, not implementation or deployment.
- Repository initially clean at `64a4626a`. No commits requested or created.
- User confirmed the sibling classifier source and ONNX preference, and explicitly
  prohibited committing weights/model release history into the application repo.
  Proposed image builds fetch verified artifacts by immutable HF commit.
- Did not access the prohibited live-provider environment file or use live APIs.

## Sources and findings

- Read the milestone index, contextual barge-in milestone, input/output handlers,
  participant/activation topology, signal/event schemas, speech runtime, Silero
  ownership and pinned Ortex Elixir/Rust implementation.
- Read sibling classifier README, model card/release manifest, cleaner v1,
  golden-fixture contract, ONNX implementation/export, and current E5 comparison.
  Source revision `294dc3fd39749ccfe353fb08d5089066199b1049`; HF model revision
  `28177ae331b8ee751ab2a1bb62da5c5632b8473f`.
- Verified primary OTP 28 scheduler/quota documentation, ONNX Runtime threading
  and compatibility docs, and Elixir Tokenizers loading/configuration docs.
  Exact links and decisions live in the durable proposal.
- HF pinned-card browser fetch failed; the local populated HF submodule supplied
  the model card, release manifest and artifact bytes. No remote publication or
  complete release-hash audit is claimed by this research.
- Existing room interrupts before publishing onset/transcripts and dispatches
  nonempty endpoint text regardless of backchannel intent. Both admission paths
  need changes. Existing cancellation/played-history machinery should stay room-owned.
- Current INT8 p99 <20 ms evidence uses four threads, not one CPU; whole-path
  latency remains unmeasured. Fourteen declared languages are not fourteen
  human-validated language profiles. Model has no dialogue context.
- Pinned Ortex can execute the graph but lacks CPU thread/spinning controls;
  CPU inference is marked DirtyIo. This needs a focused binding decision before
  shipping a CPU-bounded pool. Overflow beyond first 64 tokens needs fallback.

## Local verification

- `bin/setup` passed: dependencies, patched ExMCP, frontend setup/build and
  dev/test migrations. Setup preserved the existing private environment.
- Ran disposable `mix run --no-start --no-compile` probes; no source mutation.
  Initial model load succeeded but diagnostics called nonexistent
  `Ortex.Model.show/1`. Corrected probe confirmed synthetic tensor inference;
  model struct inspection exposed a pre-existing Inspect.Algebra incompatibility.
  Final probe avoided that inspection and completed cleanly.
- Used the sibling's existing Python environment and reference cleaner/tokenizer
  and `OnnxClassifier(threads=1)` to generate eight batch-one inputs/reference
  scores in a temporary file. Ran the same token IDs and masks through the app's
  existing pinned Ortex and Nx; softmax probabilities yielded eight matching
  labels, maximum absolute probability difference `9.775842447012906e-5`.
- Cases: `Mm-hmm.`, `Please stop for a moment.`, `Yes, yes, but change the
  appointment.`, `yes`, Kannada `ಹೌದು`, Hindi `हाँ ठीक है`, and repeated
  `wait`/`yes` reaching 64 tokens. These are smoke fixtures, not accuracy evidence.
- No timing benchmark, Elixir tokenization/cleaning parity, real call/audio,
  language validation, native binding changes or full umbrella tests performed.
  Documentation-only checkpoint; runtime checks remain delivery gates.
- Local INT8 and tokenizer SHA-256 checks match the proposed pinned manifest.
  Changed-document local link targets, code fences, trailing whitespace and
  `git diff --check` pass. Final worktree inspection contains documentation only.

## Decision and remaining work

- Wrote `docs/design/barge-in-classifier.md`, linked from milestone research.
  Existing progress checkboxes remain unchanged. Local design review is recorded
  separately from implementation evidence; no independent review is claimed.
- Recommended resident node-local INT8 inference service, participant policy,
  room-authoritative correlated cancellation/dispatch, explicit language opt-in,
  legacy fallback, CPU/thread budget and container-only verified artifacts.
- Rejected per-participant models, unbounded inference mailboxes, onset mute/
  cancellation before classification, and HTTP/Python as the initial serving path.
- Next implementation must first establish artifact/tokenizer/logit parity and
  thread-controlled capacity, then add policy/room gates with red-green tests.
  Production score thresholds, fresh per-language acceptance and CPU/load limits
  remain unresolved measurement gates, not implied defaults.
- Review also identified early answers during the end of an agent question:
  identical text can mean answer or backchannel, which this model alone cannot
  resolve. The proposal requires acceptance coverage and an explicit application
  answer phase before claiming that distinction is handled.

## Follow-up — classifier filter and structured LLM decisions

- User clarified that overlapping speech must pass through the classifier first
  when available; a backchannel skips LLM input. Without an applicable classifier,
  forward text and structured overlap context to the LLM, which returns a
  structured interruption/no-response/new-response decision.
- The initial proposal covered input filtering but selected legacy immediate
  interruption as fallback. That fallback is superseded. The revised contract
  uses the LLM for every forwarded candidate, including classifier-positive,
  uncertain, unsupported-language, disabled and unavailable cases. Legacy
  behavior is only a compatibility contract for old pinned policies.
- Inspected AgentRuntime Session, ModelRequest/ModelResponse, RequestRunner,
  ReqLLM request projection/response normalizer/provider streaming, and Call
  Engine Coordinator. Session rejects concurrent ordinary requests as busy;
  Coordinator queues them. ModelResponse rejects empty text without tools,
  while normal streaming emits text deltas. The desired control result and
  decision-during-generation path are not implemented.
- Updated the proposal with a structured overlap envelope and result fields
  `interrupt_agent`, `respond`, `response_text`; explicit no-response success;
  partial stop decisions; endpoint-gated replies; no speculative TTS/tool effects;
  bounded parallel decision requests using read-only snapshots; and one
  conversation owner for admitted history commits. Classifier timeouts bypass
  filtering; LLM decision failures have a distinct bounded degraded path.
- Reordered proposed delivery to establish the no-classifier semantic baseline
  first. Updated milestone contracts/checks and recorded local design review
  separately, leaving all progress checkboxes unchanged. No runtime code,
  dependencies, model artifacts or commits added by this follow-up.
- User then selected classifier default-on for newly added agents and deferred
  the disable control to the agent properties sidebar's Models tab. Added a
  specific implementation reminder to the design document so UI/configuration
  tasks are created at promotion, not now. Effective filtering still requires
  LLM-plus-TTS/language eligibility; disabling it preserves structured LLM
  decisions. Old published/running policy compatibility remains explicit.
- Follow-up documentation checks: both JSON examples parse, all local link
  targets exist, fences/whitespace and `git diff --check` pass. Runtime and UI
  verification were not run because this follow-up changes documentation only.
- User simplified the result to exactly two fields: `interrupt_agent` and
  `response_text`. Removed the redundant `respond` field from the active contract,
  example and outcome table. Null/nil means no response; nonempty text supplies
  the response. Both fields remain required; empty/whitespace-only text is invalid.
  Updated interim decisions to require null text and clarified that only the
  keep-speaking/no-response outcome leaves current generation untouched.
