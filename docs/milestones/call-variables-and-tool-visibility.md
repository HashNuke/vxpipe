# Call Variables and private tool projections

Status: complete as of 2026-09-09. Specification review: approved, including the
Jido Action follow-up (2026-09-08).
Forward-runtime note (2026-09-10): Jido Action references below describe the completed
implementation. The [ReqLLM agent-runtime milestone](reqllm-agent-runtime.md) migrates the
same permission, schema, privacy and tool-result contracts to data-backed runtime tools.
Prerequisites: [Definition-driven call](definition-driven-call.md), including its Jido-backed
agent loop and action boundary.
Sources: [Call Variables](../../labnotes/20260905-0405-call-definition-design.md#call-variables-are-typed-sectioned-and-permissioned); [authorization](../../labnotes/20260905-0405-call-definition-design.md#authorization-transaction); [client visibility](../../labnotes/20260905-0405-call-definition-design.md#tool-event-visibility-and-sample-debugging--approved-g5-decision).

## Runnable outcome

During the definition-driven call, the agent reads a prefilled read-only order section and incrementally updates an intake section through generated tools. The sample can deliberately show tool activity, while an ordinary client receives no tool events by default.

## Specification

- `CallVariables` is one room-scoped GenServer outside agent subtrees. It owns compiled schemas, grants, values, section/global revisions; no second mutable map in RoomAuthority. Direct bounded calls authorize trusted tenant/room/incarnation/participant, section grant, revision, datatype, and existing value-size limits without an authority round trip or current-activation/liveness check.
- Declare `call_variables.sections`; initialize only from authorized `initial_variables`. Root keys are sections; direct keys are variables. No defaults, required-variable completeness checks at any depth, extra schema-complexity caps, write-only grants, dot paths, or automatic MCP-result mapping.
- Derive `read_variables(sections)` from read grants and
  `update_variables(section,data)`/`update_variable(section,variable,value)` from read+write
  grants as a finite set of application-owned Jido Action modules; authors do not separately
  list these generated bindings and no definition-derived module is created. Register only
  the applicable actions on the activation's Jido agent. Their strict project-owned input
  schemas cover the stable tool envelopes; the handlers enforce the pinned per-call section
  schemas and grants before calling the room-owned variables process rather than storing
  authoritative values in Jido state. Complete their revision/envelope schema from the
  approved sketches.
- Generated variable-tool keys match the finite Actions' declared names. Per-call grants
  and schemas remain data checked by handlers, not generated modules. Inherit the initial
  slice's unsupported-alias diagnostic until the [ReqLLM runtime migration](reqllm-agent-runtime.md)
  is available; ordinary variable tools do not depend on remote MCP integration.
- Reads return only requested sections with revisions; any forbidden section fails the whole read without values. An authorized unpopulated section returns one `value: null`, without populating nested placeholders.
- Object updates recursively merge and preserve omitted nested values; arrays replace. Direct-variable updates address literal schema keys. Explicit null assigns/clears only where nullable, retaining the key. Validate the entire candidate atomically; errors leave values/revisions unchanged.
- Accept updates locally and hand off their exact full snapshot with turn/tool attribution to a bounded private archival port. A no-persistence host sink is explicit until the asynchronous-history slice; do not claim durability or wait for SQL. Already-submitted requests can finish after caller/agent termination.
- Rebuild a grant-filtered variable projection for model input, not as permanent private conversation history. Engine-private identity is never model-supplied.
- Apply gateway filtering before sending events: `tool_visibility` defaults hidden; metadata excludes arguments/results; full includes permitted payloads. `tool_visibility_overrides` targets participant key then local tool key. Trusted creation replaces the policy pair; browsers cannot elevate it. Sample setup explicitly selects full with no overrides. Full visibility never exposes secrets, unrestricted snapshots, or detailed R36 failure causes.

Commands also enforce their own deadlines and operation/encoded-byte bounds: a caller's
GenServer timeout does not retract queued work. Engine bindings alone receive a private
variables capability handle and scoped identity; ordinary host tools receive redacted execution metadata,
and MCP receives only declared arguments. Submitted requests can survive the originating
agent, not necessarily shutdown of the room-owned variables process itself.
Do not store raw credentials or an unrestricted plan in Jido state, tool context, status, or
checkpoints. Every action treats its private execution handle as untrusted input until the
engine resolves it to the pinned tenant/room/incarnation/participant grant.

## Implementation checklist

- [x] Add failing tests for generated tools, variable initialization/authorization/revisions, merge semantics, and public event projections.
- [x] Implement CallVariables ownership and bounded commands under the room supervisor.
- [x] Integrate generated tools and transient model projections; distinguish them from explicitly bound built-in/host tools.
- [x] Emit exact private update snapshots plus safe public metadata through separate boundaries.
- [x] Implement call-level tool visibility and trusted sample selection without adding controls to the console.
- [x] Document observed in-memory success and the later asynchronous-history projection boundary.

## Acceptance and failure checks

- [x] Wrong tenant/incarnation/grant or stale revision fails without mutation or hidden values; a mixed authorized/forbidden read returns no values.
- [x] Authored tool aliases cannot collide with generated read/update tool names.
- [x] Missing data reads null; successive partial updates populate it. Recursive address updates preserve postal_code; array replacement and nullable clearing behave correctly.
- [x] Datatype mismatch in one supplied value rejects the whole update; required missing values do not reject otherwise valid partial data.
- [x] Suspend RoomAuthority message servicing using a deterministic test boundary: variable reads/updates still complete.
- [x] Terminate an update's originating worker after submission: accepted work can finish without making another authority/liveness check.
- [x] Hidden/metadata/full and same-local-name bindings on different agents project correctly; forged browser policy never elevates visibility.

Additional acceptance gates:

- [x] Expired queued commands and oversized/malformed operations reject without mutation.
- [x] Host invocation contexts contain no private variables target, grants, or plan. This
  slice adds no MCP runtime; its later boundary remains limited to declared arguments.
- [x] Jido status, checkpoints, telemetry and errors do not disclose capability handles,
  credentials, unrestricted variables, or the resolved plan; model-visible arguments cannot
  forge a different execution identity.
- [x] Each turn refreshes only granted values/revisions; projections are not appended to
  conversation history. An update's value/new revision reaches the next same-turn model round.
- [x] Race two updates with the same expected revision: only one succeeds; the other reports
  conflict without blind retry or overwriting newer values. Caller timeout is not cancellation.
- [x] Room-owned variables shutdown is not documented or tested as guaranteed completion.

## Manual verification

1. Prefill only a synthetic order ID, grant read-only access to that section and read+write to intake.
2. Ask the agent to read the order and collect two intake values over separate messages; inspect partial values/revisions.
3. Attempt an order update and a forbidden section read; confirm rejection without leakage.
4. Compare trusted full-debug and hidden-policy calls at the network event boundary, not only visually.

## Scope boundaries

No database persistence yet, no direct browser variable-write API, no per-variable grants, automatic external-result mapping, or schema-required completeness. The asynchronous-history slice attaches EctoStorage without changing local-success semantics.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (2026-09-09): checkpoints `a312652`, `cb42ae4`, and `0d39db7`
introduced the typed commands, transactional room-scoped owner, private archival handoff,
generated Jido Actions, exact tool attribution, and transient permission-filtered model
projection. The focused suites prove authorization and non-leakage, missing reads, recursive
merge, array replacement, nullable clearing, atomic schema failure, deadlines and size bounds,
optimistic revision races, caller termination after submission, RoomAuthority independence,
Jido round continuation, and exact snapshot attribution.

Checkpoint `31e3abf` released call-definition schema `20260909.01` and implemented the
independent gateway projection policy. Compiler, session, endpoint, and RTVI projection tests
prove hidden-by-default behavior, metadata/full differences, participant-local override
resolution, same-name isolation, private session state, trusted replacement, and rejection of
browser elevation. Checkpoint `e412788` added the trusted sample's validated initial variables
without exposing them through the public request or inspection surfaces.

Rendered Chromium verification on the single Phoenix HTTPS listener at port 4000 caught a
provider-facing Action schema mismatch that scripted tool calls could not expose. Checkpoint
`428781d` added the failing model-schema regression test, switched the finite Actions to their
provider-compatible JSON envelopes, retained stricter project-owned command validation, and
made the sample's two writable variables explicit. A fresh browser room reached client and
agent `READY`; `update_variables` visibly received both values as an object, committed revision
one, returned the authorized section value, and produced the final spoken/text response. The
required `agent-browser` binary was unavailable, so this rendered interaction used installed
headless Chromium through its DevTools protocol.

Final gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix deps.unlock --check-unused`, and the umbrella suite with Call Engine `151 tests, 0
failures (1 excluded)`, Gateway `52 tests, 0 failures (4 excluded)`, and Console `20 tests, 0
failures`. The initial gate exposed a global telemetry test race; the committed provider filter
made the focused STT test and repeated umbrella gate deterministic without changing runtime
behavior. Detailed red/green commands and browser observations are in the
[implementation labnote](../../labnotes/20260909-0521-call-variables-runtime.md).

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added deadlines/bounds, private binding isolation, projection/result refresh, conflict race, and room-shutdown caveat; re-review approved.
The 2026-09-08 Jido follow-up approved finite application-owned Action modules plus
per-activation registration. It added strict stable envelopes, runtime per-call validation,
and protection of private execution context from Jido status/checkpoint/model surfaces.
Those paragraphs remain specification evidence; the completion evidence above records the
implemented and verified runtime.
