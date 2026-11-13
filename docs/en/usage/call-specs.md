---
title: Call specs and variables
description: Author and publish incoming or outgoing conversations without exposing credentials.
sidebar:
  order: 7
---

Open a tenant's **Call specs**, then create a spec or select an existing one.
Choose incoming or outgoing when creating it; direction cannot change in later
revisions. Give each agent a nonempty prompt, select its capabilities and define
the transfers it may request.

## Identity and publication

Call-spec IDs are database integers encoded as decimal strings, such as `"123"`.
They are allocated by the server and are not editable slugs or UUIDs. Names are
display labels and need not be unique. Every lookup remains tenant-scoped.

Saving appends an immutable revision. **Publish** makes a chosen revision available
to new calls and updates its incoming routes. A prepared/running call remains
pinned to its revision. Saving or publishing never dials a phone number.

In the editor, **Publish** saves valid unsaved edits first, then publishes that
saved revision. Use **Save as draft**
in the actions menu to save without publishing.

The editor's ellipsis menu opens the JSON source. Current new source uses
`schema_version: "20261004.01"`. Use the
[development example](../../../examples/call-specs/development.json) as a complete
text-call starting point; supply the selected provider credential before saving.

## Direction and entry participant

Exactly one of these direction blocks is present:

```json
{"incoming_call":{"caller":"customer","handled_by":"receptionist"}}
```

```json
{"outgoing_call":{"callee":"customer","handled_by":"receptionist","ring_timeout_ms":30000}}
```

An incoming caller is human with a receive/start-call connection. Its handler may
be an agent or human. Web connections admit a browser; phone connections name a
saved telephony service and an E.164 number.

An outgoing callee is human with a phone dial connection; its handler is an agent.
The destination is a fixed E.164 `number`, or the call-creation request's `to` when
the spec omits a number. The initial destination cannot come from a call variable.
The saved service owns caller ID and credentials. Ring timeout defaults to 30
seconds and accepts 5–60 seconds. See [Telephony](telephony.md).

## Models and speech

Agents can use **LLM + Text-to-Speech** or **Speech-to-Speech**. Human participants
can have speech-to-text. Call-wide capability defaults are inherited; an explicit
participant selection replaces the whole selection, rather than merging provider
options field by field.

Selections contain supported provider/model identifiers and public options.
`credential_name`, where used, identifies a saved binding; it never contains an
API key. Endpoint overrides, authentication headers and arbitrary modules are not
call-spec options.

The initial incoming agent defaults to waiting for input. The initial outgoing
agent defaults to a generated greeting. Explicit first-message modes can override
that behavior. Prompts should refer to destination participant keys when describing
when to transfer.

## Variables

Call variables are named sections, each with an object schema. Agents receive
explicit read/write permissions for sections. A section cannot itself have an
`enum`; individual fields, nested fields and array items can.

Variable values accept `null` by default. Set `nullable: false` to require a
non-null value at a particular schema node:

```json
{
  "type": "object",
  "properties": {
    "name": {"type":"string","nullable":false},
    "party_size": {"type":"integer","enum":[1,2,3,4]}
  },
  "required": ["name"],
  "additionalProperties": false
}
```

Here `party_size` permits the listed integers or `null`; it does not accept `"2"`.
Requiredness and nullability are separate. Missing sections/fields are not filled
automatically, and updates do not coerce values. Existing schema constraints
survive unrelated editor changes.

## Openings, waits and media policy

Optional call-level `opening_audio` plays an announcement before conversation.
Text openings need their own TTS selection, independent of the agent. File
openings use HTTPS audio. Do not embed credentials or signed URLs in the spec.
The caller cannot interrupt the protected opening before actual playback completes;
opening output is private and the ordinary room recording path stays closed.

Wait sounds cover setup, agent transfers, human transfers and joining. The editor
offers built-ins, an audio URL and silence. Previewing a sound does not modify the
call's runtime state.

Recording, transcript persistence and participant routing permissions are distinct.
An Allow choice does not override a call-wide denial or grant another participant
access to private media. Tools have separate [visibility and conversation
behavior](agents-and-tools.md#conversation-behavior).

Human STT starts on its first nonempty transcript by default. JSON authors can
set `speech_to_text.vad: true` beside the provider/model fields for earlier local
speech detection. It changes onset only; the recognizer still owns the turn's
endpoint. There is no Console VAD toggle, and the setting does not apply to native
speech-to-speech models.
