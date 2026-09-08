# Definition-driven one-agent call

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: none; start from the existing runnable umbrella.
Sources: [Canonical representation and minimal definition](../../labnotes/20260905-0405-call-definition-design.md#canonical-representation); [entry participants](../../labnotes/20260905-0405-call-definition-design.md#entry-participants-and-startup--approved-g2-decisions); [R47](../call-definition-gap-review.md).

## Runnable outcome

A trusted embedded host loads a definition with a web caller and one receiving agent, starts a room from its pinned plan, and completes the existing text/audio exchange in the sample. Editing the source definition afterward cannot change that live call.

## Specification

- Add engine-owned typed constructors for `CallDefinition`, participant/connection/capability selections, `CallInvocation`, and `ResolvedCallPlan`; ordinary Elixir input and JSON decoding converge on the same validation. Raw JSON maps never become room state.
- Use the date-based `YYYYMMDD.NN` schema-version contract. Keep resource ID/revision distinct from schema version. Choose/document the first implemented schema release during implementation; the labnote's representative JSON is a candidate, not a released schema.
- Require different existing string refs `entry_caller` and `entry_receiver` into `participants`; participant kind is human or agent. Initially run the web-caller/agent-receiver path. Do not activate the entire catalog. Keep definition key, runtime participant ID, connection ID, and fresh activation ID distinct.
- Resolve prompts, capability defaults/overrides, and supported provider options once before live startup. Provider configuration stays separate from engine interruption/duration policy. Pin the resulting immutable plan; live orchestration must not consult mutable definitions.
- Constructors return path-specific errors. Closed registries map public strings to allowed implementations; no external atom/module/function creation, executable expressions, or credentials in the public plan or public errors.
- Generate each agent's enabled tool surface from one local-key `tools` map. Start with supported registered platform/host bindings; reserve transfer derivation for the agent-transfer slice and remote bindings for the remote-MCP slice. Reject alias collisions with reserved/compiler-generated names. Unsupported enabled tools/features fail explicitly, never disappear silently. Empty transfer possibilities expose no transfer tool.
- Invocation cannot replace the definition's entry refs or the trusted tenant identity.
- Reuse current room, gateway, model, STT, TTS, and sample components. Preserve existing runtime speech/interruption behavior. This milestone's trusted startup adapter is not the production API-key/token path built in the prepared-call admission slice.

## Implementation checklist

- [ ] Write failing constructor/compiler tests for entry refs, schema version, participant identity, unsupported fields/options, secret-safe errors, and plan pinning.
- [ ] Implement the minimal typed compiler and JSON/Elixir parity for the supported one-agent subset.
- [ ] Route room startup through the compiled plan and resolve only needed initial participants/capabilities.
- [ ] Wire one trusted sample/embedded fixture to the new path without redesigning the responsive console.
- [ ] Specify supported-feature diagnostics for later milestone features; reject enabled unsupported privacy/connection/tool settings before starting providers.
- [ ] Refactor duplicated preset configuration only after the definition-driven sample tests pass.

## Acceptance and failure checks

- [ ] Missing/identical/unknown/non-string entry refs fail before room/provider start; unused catalog entries start no processes or dials.
- [ ] Invocation attempts to replace entry refs or tenant identity fail; authored aliases that collide with reserved/generated tools fail before startup.
- [ ] Equivalent Elixir and JSON definitions normalize identically; unknown schema versions and unsupported provider combinations fail clearly.
- [ ] One call has one participant per definition key; no cross-call shared runtime identities.
- [ ] Change a source definition/profile after start: the active room retains its original resolved configuration.
- [ ] A forced provider startup failure cleans up the attempted tree without silently switching providers.
- [ ] Existing text, speech recognition, streamed model/TTS output, and barge-in regression tests stay green.

## Manual verification

1. Load a synthetic caller/reception definition through the documented trusted host/sample adapter.
2. Join the existing sample console; exchange typed and spoken messages.
3. Change the configured prompt for a subsequent call and confirm the existing room keeps its original plan while a new room uses the new input.
4. Try an invalid entry ref and an unsupported provider option; inspect safe errors and confirm no orphan room/provider remains.

## Scope boundaries

No Ecto, public production admission, remote MCP, multi-party mixing, transfers, recording, or new provider integration. Reject rather than pretend to support their enabled runtime features. Tenant identity here is supplied by the trusted host; client-supplied tenant strings do not establish authority.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added reserved/generated tool alias collision checks and invocation entry/tenant non-override. Re-review approved; first position correct.
This is specification evidence only; implementation and runtime verification remain unchecked.
