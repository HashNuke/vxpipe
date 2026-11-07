# Saved MCP boundary and transfer acceptance

T7 saved web boundary and delayed-transfer checkpoint, following the saved admission
commit whose root seed 666644 passed all five gates with 4,986 tests and zero failures.
The focused acceptance and all five root gates pass. Independent adversarial source
and staged implementation review found no remaining code issues after the corrections below.

## Implemented evidence

- Extracted the shared saved-runtime fixture into an ExUnit CaseTemplate; all four
  original integration tests passed unchanged before extending the fixture.
- Seven boundary cases cover foreign-tenant publication with a distinct-server /
  distinct-credential positive control, visible zero-tool metadata, changed and
  deleted descriptors, and repository outages at preparation, startup and invocation.
  Native-only calls continue without MCP repository reads. Model/peer/plan projections
  exclude the fixture's token, headers, keyring and endpoint markers.
- Initial test expectation corrections: missing selected tools return HTTP 422
  `call_spec_resolution_failed`; invalid model arguments end the turn with an RTVI
  error response. Subsequent valid arguments execute in the same admitted call.
  These were fixture expectation corrections, not production fixes.
- Review caught a coverage gap: the changed-schema case initially saved a new spec.
  It now prepares again using the original published spec's create URL. Current
  enum constraints apply and a newly discovered tool remains absent from the
  original explicit allowlist.
- Five delayed-transfer cases use real saved publication/admission and WebRTC.
  Success removes the source, activates the destination and executes its MCP tool.
  Cold and reused-client revocation/replacement fail with the exact transfer outcome, leave
  the source present/destination absent, and accept new input on the same peer and
  call incarnation. The reused case keeps a sibling admitted room open.
  Replacement uses the real store to preserve the ID and increment generation to
  two while leaving otherwise-valid endpoint/credentials unchanged. This proves
  runtime generation pinning; it does not claim authenticated replacement UI coverage.
- The warm case reproduced a real defect: the WebRTC peer received a completed transfer
  after authenticated disconnect. A focused Connections test also returned an open
  session after credential resolution was disabled. Both failed before implementation.
  Reused sessions now validate the profile and resolve current runtime headers,
  discard those headers, and reject unavailable credentials before activation.
  They preserve the shared session on failure so a temporary outage does not tear
  down unrelated access. Per-request resolution remains authoritative for submission.
- Fixture corrections during transfer development: give each WebRTC peer a unique
  child ID; explicitly enable tool event visibility in the published transfer spec;
  validate and consume the retired source's pending transfer model request; correlate
  each new model input with its exact user text and each transfer with its prompt,
  invocation identity and terminal outcome. Do not answer arbitrary model requests.
- The adversarial reviewer rejected a mailbox-drain approach to stream quiescence:
  the fixture's immediately closed SSE response can reconnect just before revocation,
  legitimately delivering a prior authorized observation later. The warm case now
  holds its initial chunked stream open, observes its handler/reference, and releases
  it explicitly after call/connection cleanup. Owner monitoring and on-exit release
  cover failures; a bounded timeout reports failure, not successful acceptance.
  The final 16-case tagged lane passes with this controlled stream.
- Focused results: 16 tagged Console saved-runtime/boundary/transfer cases pass;
  MCP suite passes 170 tests, zero failures, 10 excluded. No source-cutover or speech
  state machine was changed; Lean is not required for this MCP reuse authorization fix.
  All five existing Call Engine wire integration cases pass after the fixture extension.

## Starting evidence

- Saved web admission now exercises real PostgreSQL publication, Console create /
  join-token / session routes, local WebRTC input, scripted model tool selection,
  real ExMCP HTTP, result delivery, authenticated disconnect and same-room failure.
  Its fixture identity does not establish real user/role/browser acceptance.
- Existing foreign-tenant, changed-schema and revoked checks stop at preparation
  or CallEngineOptions, while the original wire tests manually start IntegrationOwner.
  The next cases must retain the full admission boundary rather than invoking that
  owner directly or injecting an application catalog.
- Gateway incoming/outgoing startup already uses CallEngineOptions.build/2.
  IncomingCallAdmission owns an admission token and durable bind/release; the legacy
  start_incoming/3 path remains separate. OutgoingCallAdmission owns its distinct
  submission token. Do not replace these with TestCallStartup in acceptance.

## Initial fixture design (historical)

Extract only the shared saved-record setup, API/WebRTC/model operations and cleanup
from the passing Console fixture into focused test support after the frozen gate.
Keep protocol observations explicit in each case. Add acceptance before changing
production behavior, and use a smaller red regression for every discovered defect.

- Foreign tenant: publishing/preparing another tenant's selected connection must
  fail before any connection startup. A valid saved connection for the unrelated
  tenant must still admit and execute. Do not merely replace a tenant field in a
  manually constructed runtime plan.
- Storage outage: fail the MCP repository port at preparation, startup after
  preparation, and current request resolution in an admitted call. Native-only
  specs still admit and execute without querying that failed MCP port or falling
  back to an application catalog. Use observed port calls, not a blanket raised
  exception that may be normalized away.
- Empty catalog: connection remains visible, no phantom tool is offered, and an
  explicit missing selection fails. Native-only calls remain usable.
- Changed schema: prepare against the old catalog, change a real input constraint
  in the saved record, and reject stale admission before protocol work. Fresh
  preparation exposes the current constraint and only the explicit allowlist;
  execute valid new arguments through the admitted call.
- Deleted tool: remove the selected cached descriptor after preparation; reject
  stale startup and fresh selection without creating another connection or tool.
- Delayed transfer: start with a model-only source and a destination whose explicit
  tool references the saved MCP. Revoke or replace before requesting transfer;
  destination preparation must fail with source ownership intact. Also prove a
  successful transfer followed by model-selected MCP execution. Existing
  AgentTransferRoomTest uses the platform `transfer` tool with a destination key
  and can supply the expected observation protocol, but its injected startup must
  not replace Console admission here.
- Independent review identified a warm-connection trap: Connections.open_connection
  reuses an existing connection without resolving fresh credentials. Disconnect
  persists revocation without notifying the node-local lease registry, while a
  delayed destination keeps the room's earlier integration snapshot. Keep a sibling
  authorized room holding the same connection key, then revoke through Console and
  request transfer. Verify preparation fails and source ownership remains; a cold
  destination-only case can pass while a reused client wrongly permits transfer
  until the first tools/call. This was a source-review hypothesis at design time;
  the red acceptance and correction above now establish and address the defect.
- Already submitted request: use an explicit held HTTP response and observed
  submission, revoke while held, then release exactly once. Existing `slow` wire
  fixture has a 500 ms success fallback and cannot establish this race; add a
  controlled fixture barrier whose timeout fails rather than producing success.

## Telephony follow-on

The existing PhoneTransferScenario and TelephonyCallScenario supply configured local
carrier adapters, media admission and phone-leg fixtures, but their hand-built
PreparedCall values do not prove saved publication/preparation. Compose the real
Calls and Persistence repositories in Console, with synthetic configured telephony
credentials and real Gateway admission/leg ownership. Feed controlled carrier
media/transcripts through the existing transport fixtures; do not attach a second
unrelated CallEngine test connection and call that phone acceptance.

Managed incoming, managed outgoing and legacy incoming each need execution evidence.
The full live carrier suite is not required and must not be run without provisioned
accounts. No live-provider environment file may be read or changed.

## Independent design review

The review approved the sequence with these fixture requirements:

- Install the same observed, switchable ConnectionStore wrapper in both global
  Calls configuration and admission options before startup. Toggle it later;
  replacing only a repository option can fail at runtime-source validation and
  falsely appear to prove storage-outage handling. Record method/tenant/ID, and
  reset observations before native-only operations to prove they make no MCP read.
- Initial startup validates selections for all participants. Complete an observable
  source-room turn before revoking the delayed destination. Use public participant
  snapshots plus another input on the original peer to prove source presence,
  destination absence, prompt identity and unchanged room incarnation after failure.
  Success must remove the source, activate the destination and execute its MCP tool.
- Foreign selections fail at the earliest legitimate publication/preparation
  boundary; do not manufacture an invalid published plan. Changed-schema cases
  reject old arguments without HTTP as well as successfully executing valid new
  arguments. Deleted-tool cases observe no initialization or tool call and inspect
  both failed admission response and durable state.
- Empty connections are intentionally absent from the compiled integration map;
  assert visibility in connection metadata and no selectable tool, not an empty
  executable binding.
- A held HTTP case reports the exact handler PID/request identity and owns its
  cleanup on assertion failure. Timeout must fail/close, never synthesize success.

Order: mechanical fixture extraction and unchanged acceptance rerun; metadata and
outage boundaries; transfer success, cold failure and warm-client failure; then
held-request revocation. A transfer/lifecycle correction may be its own checkpoint.

## Scope and verification

These cases do not close independent-node renewal/revocation or rendered browser
acceptance. Telephony admissions and already-submitted invocation races also remain
open; preserve the full T7/T8 requirements.

- All five root gates pass: formatting, warnings-as-errors compilation, strict
  Credo, unused-dependency check and the full umbrella suite. Seed 181171 reports
  4,987 tests, zero failures, 214 excluded, including 876 Gateway and 543 Console tests.
- The final tagged saved-runtime/boundary/transfer lane passes all 16 cases. The
  final controlled-stream fixture also passes all five existing Call Engine wire
  cases; static gates were rerun after that fixture correction.
- Independent adversarial source and exact staged implementation review found no
  remaining source issues. Its final wording correction distinguishes the local
  WebRTC peer from a rendered browser. No credentials or local absolute paths were
  found in the staged checkpoint; documentation links and staged whitespace checks pass.
- No source-cutover or speech state machine changed; no new Lean run was required.
  No frontend UI changed, and no rendered-browser acceptance is claimed here.
