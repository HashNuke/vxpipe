# Structured message storage and call visualization

Status: checkpoint A complete, 2026-11-16. Archive and viewer compatibility is
implemented, independently reviewed and verified through its acceptance gates.
The message milestone's A/B/C/D checkpoints are complete, including native idle
and timed resumption (2026-11-17). No database migration is needed.
The user explicitly requires the
message-format milestone to cover the JavaScript call viewer and existing database
columns, not only the LLM request format. The [message design](structured-agent-messages.md)
owns the model contract; its [milestone](../../labnotes/milestones/structured-agent-messages.md)
owns these implementation tasks in checkpoint A and end-to-end activation in C.

## Source-audit baseline

The agent session's [Message](../../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/message.ex)
is an in-memory normalized struct, with role, string content, origin, tool-call
ID/name and native tool calls. It is not an Ecto message table. The inspected
durable archive is [call_facts](../../apps/vxpipe_persistence/lib/vxpipe/persistence/schema/call_fact.ex),
which stores JSON/map payload and source_policy alongside identity, attribution,
correlation, ordering and time columns. No durable plain-content conversation
table was found in this path; do not describe the change as a proven content-column
migration or promise persistent replay of every provider request.

[ArchiveRecorder.accepted_input](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/archive/recorder.ex)
currently places human content/modality into payload. The
[event projector](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/archive/event_projection.ex)
stores generated output as payload.text plus aggregated_by/will_be_spoken, with
delivery facts recorded separately. [ArchiveStore](../../apps/vxpipe_persistence/lib/vxpipe/persistence/archive_store.ex)
maps trusted fact attributes into relational columns and preserves payload.

The current [CallHistory](../../apps/vxpipe_calls/lib/vxpipe/calls/call_history.ex)
recognizes transcript facts by binary payload.content or payload.text.
[CallInspectionPresenter](../../apps/vxpipe_console/lib/vxpipe/console/call_inspection_presenter.ex)
turns those strings into message.text. The
[browser decoder](../../apps/vxpipe_console/assets/src/callInspection.ts) requires
that text string and maps snake_case fields to the client contract.
[@vxpipe/core](../../packages/core/src/types.ts) owns Message and participant
presentation types; [@vxpipe/react Conversation](../../packages/react/src/Conversation.tsx)
renders message.text and optional spoken ranges. CallConsole consumes the core
timeline store. Simply replacing content with encoded JSON would render control
JSON as dialogue unless these projections change together.

## Storage and extracted-field mapping

Use typed JSON internally/storage and JSON text only where the provider protocol
requires it. The user permits storing the JSON as-is initially. Prefer the existing
map payload for new structured records; do not double-encode an object merely
because the provider's content field is a string. A bounded decoded content object
inside the payload is sufficient; final key names follow the owning event contract.

| Existing storage field(s) | Required treatment |
| --- | --- |
| call_id/public_id, room_id, incarnation_id | Keep trusted call/event identity and deduplication; never derive identity from model JSON. |
| participant_id, activation_id, source_participant_id | Keep actual agent/source attribution from the runtime. Provider role=user is not proof of human authorship. |
| connection_id, command_id, correlation_id, tool_call_id | Keep current execution/protocol associations; no model-visible turns are required. Native tool IDs/results remain unchanged. |
| kind | Keep application event kind separate from provider role and dialogue content type. Do not make every assistant record a spoken main response. |
| sequence, public_sequence, occurred_at | Preserve monotonic/event-order contracts and actual event time; do not replace them with JSON array position or model-authored values. |
| payload | Store bounded structured content and runtime-owned output purpose/evidence under the relevant fact kind. message is text/null; agent_mode is output intent or input snapshot as appropriate. Idle action correlation is runtime evidence, not a playback outcome. |
| source_policy | Preserve retention and permission rules across all structured/raw/derived representations. |

No additional role, agent_mode or message_type column is required merely to carry
the new object. Add an indexed/extracted column only for a demonstrated query,
ordering, filtering or constraint need; record the owning invariant and migration.
Existing relational columns are sourced from runtime facts, not arbitrary model
fields. If identity is duplicated in content, validate it against trusted columns
or derive it on read; do not permit two competing identities.

The first implementation must record a concrete old/new payload mapping and
reader version strategy. Preserve legacy plain-text records using an explicit
schema/format discriminator from trusted storage/protocol metadata; do not guess
that arbitrary user text beginning with a brace is an envelope. Unknown versions
must not become fabricated speech. Do not invent old modes, purpose or attribution.
Avoid a blanket historical rewrite. If a migration is necessary after the payload
design is fixed, include it with writer/reader compatibility and rollback evidence.

## Implemented payload compatibility

New attributed facts use this trusted, per-payload format marker:

```json
{
  "content_format": "structured_agent_message_v1",
  "content": {
    "type": "participant_message",
    "participant_id": "participant-id-from-runtime",
    "message": "Okay.",
    "agent_mode": "speaker"
  }
}
```

Accepted input retains its modality alongside this object. Generated output
retains aggregated_by and will_be_spoken; separate delivery facts retain their
existing shape. Existing relational identity/order/correlation columns remain
authoritative. Neither call-details schema version changes: the outer inspection
schema remains 1 and publication schema remains 20260912.01. These already carry
extensible fact payloads. No historical backfill or immutable-publication rewrite
is performed.

Archive.MessagePayload owns the shared archive-format decoder used by authorized
Calls history and Console presentation. A missing marker preserves legacy text
literally, including JSON-looking human speech. A recognized marker accepts a
bounded decoded map or JSON string, validates the exact participant-message shape,
and requires duplicated identity to match the fact's trusted participant_id.
Unknown/null markers, unsupported types and invalid or silent content never fall
back to speech. Text is not parsed by React. Native tool facts keep their original
format.

Only generated output derives output_purpose (main_response or backchannel) from
its mode. Input mode describes the receiving agent at admission; it does not label
human speech a cue or change participant media state. Console exposes display
text plus optional agent_mode/output_purpose; Core maps these to agentMode and
outputPurpose. React labels backchannels and excludes empty speech rows while
preserving the original display text and spoken-range indexes. Audible listener
cues remain a later voice milestone.

Both archive policy owners now recursively remove transcript-bearing keys from
nested maps/lists when transcript retention is disabled, including encoded raw
content under recognized text keys. Metadata and native tool outcomes retain their
existing policy. This does not introduce raw provider capture.

## Retention and publications

At the source audit, both [CallEngine archive policy](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/archive/policy.ex)
and [Calls ArchiveSanitizer](../../apps/vxpipe_calls/lib/vxpipe/calls/archive_sanitizer.ex)
removed only top-level content/text for transcript-disabled fact kinds.
Nested message fields, cues, summaries and optional raw decision JSON would escape
that narrow filter unless the implementation updates both owning boundaries.
Sanitize structured data before any wire-string encoding; a generic recursive
map sanitizer cannot inspect secrets/text hidden inside an opaque JSON string.
Do not add raw provider-request capture or enable transcript retention implicitly.

The [fact projection](../../apps/vxpipe_persistence/lib/vxpipe/persistence/call_details_fact_projection.ex)
feeds call-details source data. The
[publication schema](../../apps/vxpipe_persistence/lib/vxpipe/persistence/schema/call_details_publication.ex)
also stores encoded contents, schema_version, source_digest/checksum and publication
identity. Updating live view alone leaves historical publications inconsistent.
Define compatible readers/versioning and deterministic projection/digests; do not
silently rewrite already published immutable artifacts or break recovery dedupe.
Apply the same authorized text filtering to live inspection, archived facts,
publications and derived summaries.

## JavaScript and presentation contract

Keep the viewer's text field as displayable text, independent of the model's
message field and provider content encoding. Project centrally; React components
must not repeatedly parse arbitrary provider JSON in rendering functions.

| Input/decision kind | Viewer behavior |
| --- | --- |
| Human speech or typed input | Show human text under the trusted participant. |
| Main assistant output | Show the appropriate generated/spoken projection using existing delivery evidence; never print a JSON control object as words. |
| Played listener cue | Show an explicitly identified backchannel/cue when permitted; do not count it as a new main response or infer a human interruption from overlapping audio. |
| listener/null decision | No empty speech bubble. Optional decision inspection is an application view, not a transcript utterance. |
| idle_timeout or engine tool completion | Application/tool context; never fabricate human speech. |
| conversation_summary | Derived context in an appropriate inspection view, not words the agent spoke. |

Add minimal optional mode/output-purpose fields to core presentation types where
needed to label cues and inspect decisions. Keep actual speaking/listening media
state separate from requested mode. Update browser decoding, core stores/types,
React rows/fixtures/stories and both live and historical call inspection together.
Playback metadata can remain in application inspection even though it is excluded
from model history. Keep existing spoken-range offsets tied to projected display
text; provider UTF-8 offsets must not be blindly applied as JavaScript UTF-16 indexes.

## Verification and checkpoint ownership

Message checkpoint A owns two explicit tasks: storage/archive/publication mapping
with compatibility/retention tests, and the end-to-end client/presenter projection
with core/react fixtures and browser inspection. These belong with attributed
input/history, not in a disconnected schema-only milestone. C verifies actual
configured calls, tools, silence/cue intent and recovery through those projections.
Voice A/B supply precise timing, C exact output-purpose/admission and E audible cues.

Required cases include legacy text, JSON-looking human text, encoded/decoded new
content, native tools, idle_timeout, no-speech decisions, main replies and listening
cues, interrupted supported prefixes, multiple participants, duplicate/replayed
facts, null/unknown versions and retention-disabled nested content. Test live and
published history parity, trusted column attribution and immutable publication
compatibility. Inspect rendered browser views at relevant viewport sizes and
states. Synthetic rendered verification is recorded in the implementation labnote;
checkpoint A acceptance passed. No database migration was performed.
