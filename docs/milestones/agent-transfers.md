# Allowlisted agent-to-agent transfers

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Remote MCP tools](remote-mcp-tools.md); [Call lifecycle](opening-audio-and-call-lifecycle.md).
Sources: [Transfer identities](../../labnotes/20260905-0405-call-definition-design.md#runtime-participant-and-transfer-identities); [transfer success/failure](../../labnotes/20260905-0405-call-definition-design.md#transfer-success-and-failure--approved-g8-baseline); [history policies](../../labnotes/20260905-0405-call-definition-design.md#initial-agent-transfer-history-policies).

## Runnable outcome

A reception agent transfers the caller to a billing agent. Billing receives only permitted variables/spoken history, the call identity and variables survive, and reception stops only after billing is ready and the room commits.

## Specification

- Derive the transfer tool from the source's simple transfers list; no list means no tool. Model receives allowed participant refs/safe descriptions, never arbitrary runtime targets/numbers/URLs. Reject alias collisions and enforce allowlist/current source activation again at execution and room commit.
- One participant identity per definition key per call; re-entry uses that identity with a fresh activation. Pinned entry refs do not change. Destination preparation starts only needed capabilities; it is not admission or conversational ownership.
- Room-authorized prepare/commit keeps source responsible until destination conversation/capabilities are ready. Emit completed only after successful control/routing commit; then terminate the entire source execution subtree. Submitted CallVariables requests may finish independently.
- Shared transfer_policy has one configurable 30s total attempt budget; phases do not reset it. Failure/timeout terminates destination attempt and returns a typed outcome to the source; late callbacks cannot commit or revive old output.
- If permitted source capabilities need restoration, allow exactly one bounded attempt; restart loops cannot reset it. If none works and no usable conversation remains, end. Detailed cause stays internal even with full sample tool visibility; public/agent outcomes are generic.
- Support approved fresh/all_spoken/last_n_spoken/selected history projections without summarization. Include only permitted confirmed user/played assistant utterances and destination-readable variables, never system prompts, hidden tools/scratch state, or generated-but-unplayed text. Re-entry does not replay first greeting.
- This slice runs agent destinations under its supported media policy. Reject presence-route combinations not enforceable until the mixing slice; never ignore privacy at transfer. Later human adapters use the same engine contract, not a named-transfer workflow.

History modes are closed: fresh has no prior model history; all_spoken contains permitted
confirmed user/played assistant utterances; last_n_spoken bounds that completed-spoken window;
selected sends no history, only allowlisted typed variables and an explicit reason. Destination
preparation may become ready but greeting/TTS/main output stays inaudible to the caller until
commit, while the source retains conversation.

## Implementation checklist

- [ ] Red-test compiler-derived transfer schema/aliases and runtime source/target authorization.
- [ ] Implement room prepare/commit lifecycle, distinct participant/activation identities, and supervised destination/source ownership.
- [ ] Integrate private destination history/variable projection and source termination after commit.
- [ ] Implement total deadline, late-result exclusion, typed failures and single restoration budget.
- [ ] Emit private transfer history and safe client outcomes without adding new RTVI-core messages.

## Acceptance and failure checks

- [ ] Allowed transfer succeeds; injected target, wrong/stale source, duplicate preparations, and generated-tool alias collision fail before unauthorized startup.
- [ ] Destination startup fails or deadline expires: source remains responsible, no completed event, destination cleaned up.
- [ ] Commit preserves call/variables/entry refs; source capability/tool workers terminate, old output cannot reach new activation.
- [ ] Re-enter agent: same participant ID, new activation, no greeting replay; permitted history only.
- [ ] Restoration attempts exactly once; detailed failure does not leak through speech or full-debug events.
- [ ] Empty transfers expose no tool. Every history mode excludes private prompts/tool data
  and generated-but-unplayed text; selected contains only allowed variables/reason.
- [ ] Block destination preparation: source can converse and destination cannot speak to caller.
- [ ] One 30s budget starts at accepted preparation across all phases; failed-commit/deadline
  races and late completion produce no transfer.completed event or stale destination output.

## Manual verification

1. Use caller/reception/billing catalog and synthetic protected order variables.
2. Ask reception to transfer; compare identities, variables and billing's allowed history.
3. Exercise a failing destination and controlled deadline; confirm reception handles the outcome.
4. Try an unauthorized destination and re-entry; inspect safe events and no stale speech.

## Scope boundaries

No human bridge, arbitrary dialing, named transfers, graph/on_success hooks, generalized concurrent consultation, transfer-history summarizer, or caller reconnection. Presence-driven media is implemented next, not silently bypassed here.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation remains partial; do not mark this slice complete because its specification has
been reviewed or because the compiler boundary below exists.

Partial implementation evidence (2026-09-10): schema `20260910.04` accepts unique, non-empty
definition-local agent transfer refs and rejects malformed, duplicate, missing, self, and human
destinations with indexed paths. The compiler derives one `transfer` descriptor only for a
non-empty list, keeps runtime participant/activation identities in its private binding, projects
only safe refs/descriptions, validates the destination with a closed JSON Schema, applies the
ordinary participant-local visibility override, and pins conversation admission to `blocking`.
Both conversation modes retain the common independently supervised worker contract; this derived
tool adds no inline execution route. Authored `transfer` aliases remain reserved. `PlanStartup`
still rejects all transfer-enabled plans, so this checkpoint cannot start a destination or mutate
room control before the prepare/commit implementation exists. Four focused transfer compiler tests,
the 18-test compiler/descriptor/startup group, and the complete 263-test Call Engine suite passed;
Calls, Gateway, and Console passed 36, 66, and 57 tests respectively.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Specified history modes, precommit destination silence/source continuity, empty-list and total-deadline races; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
