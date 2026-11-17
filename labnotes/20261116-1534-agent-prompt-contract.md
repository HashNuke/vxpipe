# Agent prompt and mode contract

Status: documentation/design follow-up, 2026-11-16. No runtime changes, provider
requests, tests of runtime behavior or commits. Existing worktree research is
preserved. The previous [ordered Q&A](20261116-1107-message-format-questions.md)
remains a historical source audit; this note records the user's next questions.

## User requests and answers

- [x] Explain and document bypassing LLM generation for known greeting text.
- [x] Give a caller_idle use case and chat transcript.
- [x] Give a call_state_changed use case and chat transcript.
- [x] Create editable shared platform prompt sources, including tools and summaries.
- [x] Make JSON-string encoding explicit for all provider text-content messages.
- [x] Keep playback information excluded from assistant history in design/checkpoints.
- [x] Analyze replacing interrupt_agent with assistant agent_mode.

### 1. Known greeting text

Yes: if wording is known, the LLM-plus-TTS path should send it directly to TTS
and retain the supported assistant speech for later model history. This already
exists as first_message=fixed: FirstMessage selects fixed_greeting, and Coordinator
calls Session.record_assistant and emits text without a generation request.
Only the existing explicitly generated setting asks the LLM to choose wording;
wait_for_input sends no greeting. Preserve that distinction rather than remove
existing generated configurations without a request. The new history boundary
must still handle a fixed greeting that never plays or is interrupted; generated
text cannot be treated as fully delivered simply because recording is earlier.
STS uses its provider-native opening mechanism and does not receive the LLM JSON
result protocol. Fixed text does not need a fabricated greeting_request event.

Sources: [FirstMessage](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/first_message.ex),
[Coordinator](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/agent_runtime/coordinator.ex).

### 2. caller_idle

Use case: the agent asks which appointment time the caller wants, the caller
provides no new input, and the configured eligible idle interval elapses. The
unchanged transcript cannot tell the model that time passed. The application
notification allows a contextual check-in such as “Would you like me to repeat
the options?” The event itself is never spoken or attributed to the caller.
If the caller instead said “Give me a minute to find my booking number,” authored
waiting instructions can choose continued silence. The validated null response
is proposed behavior, not a claim that the current plain-text runtime already
implements it. No new timeout default, repeated nagging or hangup policy is added.

The design now includes a spoken transcript and chronological role/content JSON
exchange with encoded string content. Existing eligibility remains unchanged:
ready/opening complete, no held participant, active agent turn/background tool
or active target speech, with target connection and text capability available.
This is not a backchannel mechanism for pauses during a speaking human's turn.

Sources: [CallerIdle](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/caller_idle.ex),
[CallLifecycle](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_lifecycle.ex),
[example](../docs/design/structured-agent-messages.md#idle-example-and-chat-transcript).

### 3. call_state_changed

Use case: another authorized participant changes shared appointment.status from
pending to confirmed. This fact is outside the current agent's tool exchange and
spoken dialogue. The caller next asks whether the appointment is confirmed.
The next otherwise admitted request needs that new permitted fact; a static
system instruction cannot convey a changing value. No request is triggered by
the state update alone. The design includes both the spoken/app transcript and
actual string-content inputs with existing Call Variables section values and
revisions. Do not duplicate a result already conveyed solely to repeat a fact.

This event name remains proposed. Today ModelContextSource fetches permitted
Call Variables/transfer context, and RequestProjection appends it to the system
runtime-state text for each request. Appending only initial state/actual relevant
changes preserves the prior prefix. On-demand read_variables is an alternative,
but requires another tool/model round; unrelated runtime events do not belong in
either projection. Calls with no such business context need no state event.

Sources: [ModelContextSource](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/agent_runtime/model_context_source.ex),
[CallVariables read shape](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_variables.ex),
[RequestProjection](../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/provider/req_llm/request_projection.ex),
[example](../docs/design/structured-agent-messages.md#business-state-example-and-chat-transcript).

### 4. Editable platform prompts and summary instructions

Created three editable prompt drafts under docs/design/prompts. The shared
agent-system file owns attribution, tools, idle/state context and summary reading.
The LLM dialogue file owns the existing structured result contract and mode rules;
it remains the previous approved contract pending the user's mode-only choice.
The compactor file specifies facts, attribution, goals/preferences, commitments,
corrections/negation, unresolved questions and actual completed/failed/unknown tool
outcomes. Summaries remain data, not instructions or new permissions/results.

These files are not wired into runtime yet. Milestone C now requires automatic
composition with each agent's authored instructions, package inclusion, single
editable sources, prompt revision pinning and provider-boundary checks. Shared
behavior applies across call-spec agents; STS excludes the LLM JSON overlay and
keeps its native wire/media/tool protocol. Actual tool definitions stay in native
provider tool schemas; prompts describe usage without duplicating catalogs or
embedding secrets/pending inventories. The separate compactor uses its own file.

Sources: [shared prompt](../docs/design/prompts/agent-system.md),
[dialogue prompt](../docs/design/prompts/llm-dialogue-system.md),
[compactor prompt](../docs/design/prompts/conversation-summary-system.md),
[current compactor](../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/compaction_projection.ex).

### 5. JSON strings at the provider boundary

Agreed: prior object-valued examples were readable internal payloads, not literal
text-content requests. Structured participant/platform/assistant-history/summary
payloads must all be JSON-encoded to strings where a provider expects text, with
normal outer request encoding afterward. Existing encoded tool/engine strings
must not be encoded again as JSON string literals. Native tool-call blocks keep
their own protocol. Providers with content-part APIs carry JSON text in supported
text parts. Do not assert one wire shape for every provider. Output text is decoded
and schema-validated before TTS. The design includes exact string-content examples
and milestone A checks encoder escaping, Unicode, no double encoding and actual
submitted request/prefix stability.

Source: [encoding contract](../docs/design/structured-agent-messages.md#json-serialization-at-the-provider-boundary).

### 6. Playback information

Confirmed in the current design and message/voice milestone tasks: only supported
spoken text enters ordinary assistant history. Delivery metadata, generated versus
played diagnostics, uncertainty and late corrections stay application concerns.
No speech_delivery or speech_delivery_correction model event is reintroduced.

### 7. Assistant agent_mode instead of interrupt_agent

This is a useful proposed field for the desired state, but input and output have
different ownership: input mode is runtime-observed at input admission; output
mode would request a transition. Runtime current-target, endpoint and stale-result
validation still applies. A returned mode never proves audio played.

Some cases map naturally: listener to speaker+text requests a reply; speaker to
listener+null requests stop-and-listen; speaker+null can mean continue existing
output. The ambiguity is speaker+new-text while the agent is already speaking:
both replace-current and finish-current-then-reply produce the same mode/text.
Mode alone cannot preserve both behaviors. Do not give listener+text an invented
meaning or make ordinary dialogue text into a backchannel to fill this gap.

An optional asynchronous question asks whether the user wants to retain both
behaviors or make all admitted speaker+new-text replace the eligible response.
No answer has been received yet. Preserve the existing four-outcome contract
until the decision is explicit; the newer proposal is documented as open, not
implemented or silently approved. If new text always replaces, a mode-only
contract can deliberately drop the independent deferred-response choice. If both
are retained, action/ordering needs a separate representation. The exact point
of switching from listener to speaker and preparation-state semantics must also
be reconciled with the chosen contract; do not retain contradictory mode owners.

## Verification and review

- Message tasks remain 23 across A/B/C; voice tasks remain 72 across A–F, all
  unimplemented. Fixed greeting, serialization and prompt-source requirements
  strengthen existing meaningful checkpoints without creating extra milestones.
- Documentation checks passed across 25 changed Markdown files: 315 local links,
  51 heading anchors and 15 parsed JSON blocks. Seven nested content-string
  examples decode once to objects, including preserved native tool acknowledgment.
  Removed playback/classifier fields remain absent from model examples.
- Verified message A8/B7/C8 and voice A11/B4/C17/D12/E17/F11 checklists remain
  open; index remains 65 total/50 complete/15 pending. Historical completed Scribe
  evidence is unchanged. `git diff --check` passed.
- Independent Astra xhigh focused review found no material findings. It verified
  fixed-greeting source behavior, the existing Call Variables shape, JSON strings,
  shared/LLM/compactor ownership, STS exclusion of the JSON overlay and checkpoint
  coverage. The assistant-mode decision remains open; review does not choose it.
  No runtime behavior, live provider/browser check or implementation completion
  is claimed.
