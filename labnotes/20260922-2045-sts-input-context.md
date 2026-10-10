# STS input context boundary

## Scope and baseline

New independent checkpoint begins from clean `e839119d`; parent reports integrating
the earlier tool group as `176be9d2` with 102 tests and four static checks green.
Those are parent-reported integration results, not new runs in this worktree.

Allowed runtime scope: Session, Input, STSInput, STSProvider, descriptor opt-in,
minimal Channel input hooks and a new cohesive pure context owner. Parent owns
Event/STSOutput, capability and Google response integration. No private completion
or cross-origin cutover implementation belongs here.

## Inspection and pre-runtime design review

Read Session's bounded commands, Input's claim/dispatch, STSInput support and text
evidence rules, Channel consumer/readiness/claim/result/deadline handlers and
Descriptor validation. Read the parent's Google response-ownership design without
changing the parent worktree. Channel already provides the required ordered slot;
no second queue/process is needed.

Recorded milestone tasks and separated review in `labnotes/20260922-2102-sts-input-context.md`
before tests or code. Proposed ResponseContexts stage/accept/rollback/status API
and exact-reference future retain/release seam sent to parent. Last-root retention
and obligation bounds need coordination before runtime implementation. No automatic
eviction or current-context fallback is acceptable. Until a release authority is
defined, retain accepted origins to allocation teardown and reject a seventeenth
distinct origin; same-origin reuse does not allocate another entry.

## Verification state

Parent approved the pure stage/accept/rollback/status API and interim retention.
Recorded the explicit parent follow-up (bounded obligation holds, authorized root
retirement and >16 retired rotations, no unbounded tombstones) before tests/code.
No retain/release implementation or further architecture hold is needed.

All commands ran in the Call Engine child with `ERL_FLAGS='+S 2:2'`, using the
isolated worktree's existing build and dependency copies. No root, native,
hosted, load or billable runs performed. Prior checkpoints are unchanged.

New-test command:

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/speech/sts_input_context_test.exs test/vxpipe/call_engine/speech/response_contexts_test.exs --seed 0
```

- Red handle `62634`: terminal exit 2, 12 tests/12 failures. Missing owner/API
  and opt-in descriptor validation prevented the new boundary from working.
- Intermediate `91153`: terminal exit 2, 12 tests/3 failures. Fixed test-only
  misuse of OTP's send_request arity and synchronized fixture initialization.
- Intermediate `58722`: terminal exit 2, 12 tests/1 failure. Source inspection
  showed existing input readiness does not wait for ready-event acknowledgement;
  changed the probe to withhold actual provider readiness. No production readiness
  policy change was made.
- Green `20217`: terminal exit 0, 15 tests/0 failures after adding missing-callback,
  provider-as-consumer rejection and unclaimed-input expiry coverage.
- Green regression `34490`: terminal exit 0, 74 tests/0 failures after formatting.
- Final regression/static command `26692`: terminal exit 0, 74 tests/0 failures;
  exact-path format check and diff whitespace check also passed before that run.
  Runtime review verified only authorized input/descriptor/Channel hooks changed;
  no guessed retention release or response protocol was added.

Exact regression command:

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/speech/sts_input_context_test.exs test/vxpipe/call_engine/speech/response_contexts_test.exs test/vxpipe/call_engine/speech/sts_session_test.exs test/vxpipe/call_engine/speech/input_contract_test.exs test/vxpipe/call_engine/speech/descriptor_test.exs test/vxpipe/call_engine/speech/sts_provider_contract_test.exs test/vxpipe/call_engine/speech/sts_conformance_test.exs test/vxpipe/call_engine/speech/sts_output_test.exs test/vxpipe/call_engine/speech/deadline_test.exs test/vxpipe/call_engine/speech/sts_turn_control_test.exs --seed 0
```

## Parent handoff seam

Parent confirmed it owns response event queue gating after integrating this slice.
`ResponseContexts.status/2` and `Channel.response_contexts` are available; stage
is stored before provider invocation, and exact claimed-command result handling
accepts or rolls back within the original budget. Synchronous Event.emit must
return after bounded local staging, not wait for consumer acknowledgement, or the
provider cannot return its input acceptance. No Event/STSOutput, capability,
Google, grant or retirement implementation was changed here. The early-event
regression uses existing input_submitted evidence, not the parent's new event.
