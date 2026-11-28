---
title: Call specs and variables
description: Author and publish incoming or outgoing conversations without exposing credentials.
sidebar:
  order: 7
---

Open a tenant's **Call specs**, then create a spec or select an existing one.
Choose incoming or outgoing when creating it; direction cannot change in later
revisions. In the editor, give each agent a prompt of at least 100 characters, select its
capabilities and define the transfers it may request. New agents start with the
Hangup tool enabled; you can edit or remove it in Tools.

## Identity and publication

Call-spec IDs are database integers encoded as decimal strings, such as `"123"`.
They are allocated by the server and are not editable slugs or UUIDs. Names are
display labels and need not be unique. Every lookup remains tenant-scoped.

Saving updates the working draft without changing the published version number.
**Publish** creates the next version for changed content and updates its incoming
routes. Publishing unchanged content keeps the live version and routes. A
prepared/running call remains pinned to its original immutable source revision.
Saving or publishing never dials a phone number.

The editor and list show **v6 Published** or **v6 · Unpublished changes**, and
**Draft** before the first publication. Unsaved browser edits are marked separately.
Click the editor badge to see the latest three published versions and dates, with
**Live** marking the current one. Saved unpublished changes appear above them with
the last-save date. This is a reference list, not a version-switching control.
Existing installations may initially show only their known current publication.

In the editor, **Publish** saves valid unsaved edits first, then publishes that
saved revision. Use **Save as draft**
in the actions menu to save without publishing. A draft can retain a written opening while its default voice is being configured.
Publication requires that conflict to be resolved. Other validation errors,
including unsupported model/tool combinations, still block saving. A failed save creates no
revision and keeps your unsaved edits in the editor. Errors point to the relevant
participant or setting.

The editor's ellipsis menu opens the JSON source. Current new source uses
`schema_version: "20261128.01"`. Use the
[development example](../../../examples/call-specs/development.json) as a complete
text-call starting point; supply the selected provider credential before saving.

## Direction and entry participant

Select the Entry card to open **Call settings → Connection**. Set the handler,
connection and opening here. For outgoing calls, this tab also sets the ring
timeout. The caller or callee remains a human participant in the source.
Its transcription uses the human model default and its media follows call policy.

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

### Participant guardrails

In **Call settings → Models**, select a Decisions provider, model and saved credential. The available providers are OpenAI Decisions, Gemini Decisions and Jev. Open an agent’s **Guardrails** tab to add questions. Each agent has its own lists and shares the call’s Decisions selection. An empty list makes zero provider requests for that event.

| Event | When the questions run |
| --- | --- |
| Before turn | When an LLM + TTS agent receives final speech or typed input. |
| After turn | Before the agent releases a reply that contains speech, including speech proposed alongside tools. A tool-only reply skips this event. |
| Before outgoing transfer | When the sending agent requests a transfer to an allowed destination. This also applies to native speech agents. Configure allowed destinations on the agent’s transfer tool. |

For each question choose **Required answer**, set **Probability threshold** and optionally write a **Response**. The score always measures the probability of Yes. With the default threshold of 0.70, required **Yes** passes at 0.70 or above. Required **No** passes below 0.70. For example, “Is the caller requesting someone else’s account details?” with required No will block at exactly 0.70.

The call-spec JSON stores each question inside the participant. A new question can be written as follows.

```json
{
  "guardrails": {
    "before_turn": [
      {
        "question": "Is the caller requesting someone else's account details?",
        "required_answer": "no",
        "probability_threshold": 0.70,
        "response": "Ask the caller about their own account."
      }
    ]
  }
}
```

The backend assigns each new question an `id` when saving the call spec. Keep the returned ID when editing or reordering an existing question. The API accepts numeric thresholds from 0 through 1 in increments of 0.01. An omitted threshold defaults to 0.70.

When a check blocks, each failed question contributes one private line to the conversational model, in the order shown in the editor. Your response is passed verbatim. A blank response produces a line such as `Failed guardrail: Is the caller requesting someone else's account details? Required: No.` The response guides the model when it composes its reply. Rejected input, drafts and temporary feedback stay out of its subsequent conversation history. A checker error ends the affected response without releasing speech or tools.

When speech, an ordinary tool and a transfer are proposed together, the speech and transfer checks run together. Both must pass before any part of the proposal runs. Transfer and hangup wait for earlier ordinary tool work in the batch to finish, including non-blocking tools.

### Conversation languages

In **Call settings → Models**, choose conversation languages in priority order. The call spec stores the complete selection at the top level.

```json
"conversation_languages": ["en-GB", "en-US", "es-MX"]
```

Each speech model uses the hints it supports. For example, Scribe receives English as its primary language and Spanish once as a secondary language. A model that accepts a single hint skips unsupported selections and uses the first one it recognizes. Models that support regional tags can receive both English variants. Flux English uses no hints. Flux Multi keeps its multilingual model identity even with just one English hint.

Choose **Automatic** to clear the list and use each provider’s default behavior. Models without language hints and models that recognize none of the selected languages receive no hint. Existing call specs without this field retain their per-model language settings, including Scribe’s legacy `options.language_code`. Setting the call-wide field explicitly overrides those settings, including when the list is empty.

## Variables

Call variables are named sections, each with an object schema. Agents receive
explicit read/write permissions for sections. A section cannot itself have an
`enum`; individual fields, nested fields and array items can.

In **Call settings → Variables**, choose **Add section**, then **Add variable**
inside that section. To grant access, select an agent participant and open **Variables**.
Choose **No access**, **Read**, or **Read and write** for each section. The
permission applies to every variable in that section.

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
A text opening such as `{"type":"text","text":"Welcome."}` uses the voice in
**Call settings → Models**. With speech-to-speech defaults, choose **Audio file
URL** or turn opening audio off. If the model changes after a message has been
written, the draft retains the text until you select a different opening type.
File openings use HTTPS audio. Do not embed credentials or signed URLs in the spec.
The caller cannot interrupt the protected opening before actual playback completes;
opening output is private to the caller. When the call is recorded, the opening
is captured on the room track, never on the caller's track.

In **Call settings → Media**, wait sounds cover setup, agent transfers, human transfers and joining. The editor
offers built-ins, an audio URL and silence. Previewing a sound does not modify the
call's runtime state.

Recording is opt-in and transcript persistence is separate. In
**Call settings → Media**, **Record audio** defaults to **Off**; turn it
**On** to record the call. A participant-level **Don't record** silences that
participant's present interval in every track, and a call-wide off records
nothing. An Allow choice elsewhere does not override a call-wide denial or grant
another participant access to private media. Tools have separate [visibility and
conversation behavior](agents-and-tools.md#conversation-behavior).

A recorded call downloads from its call-details page as one Matroska file
(`recording.mka`). Tracks are named by participant key — the first connection
is `caller`, later reconnections append a count (`caller-1`, `caller-2`) —
plus a `room` track carrying audio the room itself played, such as the opening
and wait sounds. Every track starts at the same room-clock zero, with silence
covering gaps and the time before a track starts.

Human STT starts on its first nonempty transcript by default, and the
recognizer decides when the caller's turn ends. JSON authors can set
`speech_to_text.vad: true` beside the provider/model fields to let local voice
activity detection decide both instead. The turn starts when local speech is
detected. It ends after about 0.8 seconds of local silence. If the caller speaks
again within that window, the same turn continues.

When the turn ends, Vxpipe asks the recognizer to finalize its text. ElevenLabs
Scribe, Deepgram Flux and Gemini Transcribe Live support this. Cartesia Ink 2 and
Morse have no finalize command, so Vxpipe waits a short, bounded time for their
final text and otherwise ends the turn with the latest text it received. Pauses
shorter than the silence window stay in one turn, even when the recognizer
splits them into segments.

There is no Console VAD toggle, and the setting does not apply to native
speech-to-speech models.

### ElevenLabs Scribe models

An ElevenLabs connection supports both `scribe_v2_realtime` (Scribe v2 Realtime)
and `scribe_v3_live` (Scribe v3 Live). Select either model under Speech to text in
the editor, or set it inside a call spec’s `capabilities`:

```json
{
  "speech_to_text": {
    "provider": "elevenlabs",
    "model": "scribe_v3_live"
  }
}
```

Use `credential_name` when selecting a named connection. Both models use the same
ElevenLabs API key. Existing specs keep their selected model; the default remains
Scribe v2 Realtime. Both use Vxpipe's existing transcript onset and inferred-gap
turn handling, described in [the speech runtime](../development/speech-runtime.md#input-and-caller-turns).
