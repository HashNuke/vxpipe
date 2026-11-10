# Native STS tools research

## Request and scope

Research how provider-native speech-to-speech agents can use platform tools such
as transfer and the tenant's connected MCPs. Inspected `f9eefd6a` on `main`.
Documentation only; no deployment, provider API invocation or runtime change.

## Findings and decisions

- Native tool codecs and supervised execution already exist. Participant transfer
  works in Morse/GPT-Live room fixtures; ElevenLabs has a compiled-room host `ping`
  loop. Avoid describing native STS as having no tools.
- `SpeechToSpeechActivation.resolve/3` compiles without a remote owner, rejecting
  MCP bindings, then discards executable descriptor bindings. The native tree
  has no MCP owner/session subtree.
- Native room dispatch handles blocking host and participant-transfer bindings;
  other bindings silently defer. Injected variable tools are absent from its
  original-participant-map lookup. Reuse the shared descriptors/executors and
  existing authorized platform effects.
- Reuse participant-owned MCP sessions in the native allocation tree, with exact
  ownership, bounded readiness and rollback. Keep tenant catalog maintenance
  separate. No new database/job system, shared pool or LLM decision loop needed.
- Existing completion plan Package 1 already covers the binding gap. Its D4
  amendment selects one native result per call and per-model late-result support.
  Do not restore the older interim-running/private-continuation proposal or add
  a duplicate milestone.
- Native completion leases are never acknowledged; 16 retained invocations exhaust
  an allocation. The separate five-second execution deadline may truncate useful
  MCP/transfer work. Include bounded settlement and configured budgets in the
  integration slice, rather than broadly redesigning execution.

Durable findings, official sources and acceptance scope are in
[native STS tools](https://github.com/HashNuke/vxpipe/blob/1914be98/docs/development/native-sts-tools.md).

## Research method and evidence

- Read startup, provider adapters, native allocation tree, room authorization and
  dispatch, shared invocation handlers, completion registry and participant MCP
  ownership design/implementation.
- Used the OpenAI Docs skill for official GPT-Live/Realtime documentation. Checked
  the actual GPT-Live delegation guide rather than applying classic Realtime event
  envelopes to that adapter. Checked ElevenLabs Realtime compatibility and session
  tool schema, and Google's current Live tool matrix.
- Google's old documentation URL redirects to AI Studio; the browser tool could
  not parse its Markdown content. A read-only HTTP fetch of the official page
  succeeded. The fetched matrix includes Gemini 3.8 Live, unlike the older search
  excerpt. Async capability is per model and still requires adapter wire support.
- Ran four focused Call Engine test files listed in the research document:
  **34 tests, 0 failures**, seed `866416`. No broader umbrella rerun was necessary
  for this documentation-only change.
- A temporary test copied the existing Morse transfer-room fixture, selected
  platform `get_current_time`, sent `TOOL get_current_time {}`, observed
  `ToolCallStarted`, synchronized with the room via `:sys.get_state`, and asserted
  a pending call with an empty invocation registry. **1 test, 0 failures**,
  seed `381112`, six unrelated fixture tests excluded. This proves the current
  defect, not a fix. The scratch test was not added to the repository.
- An initial scratch run selected no tests because its filename lacked the
  `_test.exs` suffix. Corrected the name and ran from the owning child application;
  only the subsequent executed probe counts as evidence.

## Review and completion

- Independent reviewer checked current implementation claims, official provider
  sources, Package 1/D4 scope and recorded test output. No actionable findings;
  no additional framework or milestone is needed.
- Removed an unnecessary claim about ElevenLabs' internal model architecture
  during source verification because the linked guide did not substantiate it.
- Local documentation links and whitespace checks pass. Runtime code and milestone
  completion checkboxes remain unchanged. Commit and push this documentation
  checkpoint under the user's standing instruction.
