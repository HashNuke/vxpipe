# Authoring call specs in Console

Sign in as an installation operator, open a tenant's **Call specs** page, then
choose **New call spec** or an existing spec's name. The Calls column opens that
spec's calls. New specs first ask for **Incoming call** or **Outgoing call**;
outgoing calls also require a configured phone service. The chosen direction
cannot be changed in the editor, JSON or later saved revisions. Create a separate
spec for a different direction. The editor does not start test calls. New specs receive a server-generated public
UUID. The ID is not editable; saves append revisions under that same ID.
Rename the call spec by selecting its name in the editor header. Call settings
contains the call configuration; it does not repeat the name field. The **Entry**
card represents the caller (or outgoing callee); configure that participant on its
card, including **Handled by** on its Connection tab. Call settings shows **Incoming call**
or **Outgoing call** at the other end of its title row.

The canvas shows participants and transfer destinations. Human cards show only
their name and icon. Participant descriptions are omitted from canvas cards and
transfer destination lists; destination search matches participant keys. Agent
cards show their name, tool count and the number of variables they can write. Variable counts include
top-level properties in writable sections; nested objects count as one variable.
Prompts stay in the agent inspector. Select a participant to
edit its fields; **Call settings** opens model defaults, variables and call
policies. On a phone, these controls open in a side sheet. Model and voice choices
come from the installed provider catalog. Choosing a provider selects its
recommended model and voice without adding recommendation badges to their names.
Provider and Model share a row. Credential selection is managed outside this editor.
Existing saved selections are preserved. A public
speech model such as `flux` and its `options.voice` remain separate in the source;
the provider adapter composes its concrete model ID.

New agents, including the initial agent in a new spec, start with an empty system
prompt. Enter instructions in the agent's **Prompt** tab before saving. Empty or
whitespace-only prompts block saving the call spec.

Participant forms have no Description field. Put transfer instructions in the
agent's prompt, referring to destination participant keys. Existing optional
`description` values remain in the saved JSON and can be edited there; the runtime
still includes them in transfer-tool destination details when present.

An agent's **Models** tab offers two model types: **Speech-to-Speech** uses one
speech model; **LLM + Text-to-Speech** shows a language model and a voice model.
Changing type removes incompatible selections and supplies missing selections
from the installed catalog's recommendations. Other agents keep their effective
models. Human participants' **Models** tab contains only **Speech to text**.
Participant media policies live in **Media**.

Human STT starts a turn when its first nonempty transcript arrives. API users can
set `speech_to_text.vad: true` for earlier local speech detection; omission means
false. There is no VAD control in Console. Existing values remain intact when
providers or models are changed.

**Call settings → Models** groups defaults under **AI agents** and **Human
participants**. The AI group lets you choose either **LLM + Text-to-Speech**
(language and voice models) or **Speech-to-Speech**, showing only that type's
fields. Changing this type switches all AI agents, removes incompatible model
selections, and fills missing defaults from catalog recommendations. Compatible
provider/model overrides stay intact. Each agent can subsequently choose its own
type in its **Models** tab. The human group's **Speech to text** is unchanged.

In **Call settings → Variables**, each section is a card with variable rows.
Each section holds one object. Enumeration is supported only on individual
variables, including nested fields and array items. A section schema cannot have
an `enum`; the editor and backend reject it. Remove any existing section-level
`enum` through the full JSON editor before saving or using that spec. A variable
inside the section can have the array type, including an array of objects.
Each section has a shaded header with a list icon and a compact name. Variable
rows are compact and indented beneath it, with type and required status beside
the field name. Configured constraints appear as `key: value` tags alongside the
section name, wrapping when needed. The header’s plus button and bottom **Add
variable** button both open the variable modal. **Add section** and the section’s
edit button open the same modal for its name. Changes apply only with **Add
section** or **Save section**; **Cancel** discards the draft. Renaming preserves
agent permissions and phone-routing references to that section.

**Add variable** and a row's edit button open the same modal for its name, type,
required status, enum values and constraints, including nested schemas. Changes
apply only with **Add variable** or **Save variable**; **Cancel** discards the modal
edits. New sections and newly selected object types default to declared fields
only; there is no Additional properties control. Access is configured exclusively
in each agent's **Variables** tab.

**Speech to text** transcribes incoming participant audio. The editor does not show
an **Output speech to text** control. Existing source values remain intact when
other models are edited. The source field `output_speech_to_text`
is the fallback for generated agent audio when a speech-to-speech provider declares
that it has no output transcript. The installed Google Gemini 3.8 Live (`gemini-3.8-live`) and OpenAI GPT-Live 1
(`gpt-live-1`) adapters both provide output transcripts; leave this fallback unconfigured for
them. The credential-free Morse test provider can disable transcripts with
`options.output_transcript: false`; that configuration requires output STT.
The compiler rejects missing fallback STT in that mode and duplicate STT when the
provider already supplies transcripts. See Google's [Live API transcription](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
and OpenAI's [GPT-Live transcript events](https://developers.openai.com/api/docs/guides/live-conversations).

**First message** offers **Wait for input**, **Generated**, and **Fixed text**.
It shows the effective choice directly: incoming agents wait for input, while the
initial outgoing agent generates an introduction by default. Selecting the
direction's default omits the override; there is no separate Default item.

**Save as draft**, in the vertical ellipsis menu beside **Publish**, creates the
first immutable revision or appends a revision to the same spec. It does not
change which revision is published. **Publish** publishes
the saved revision and is available only when the draft has no unsaved edits.
The header shows the open and published revision numbers. Editing while a save is
in progress retains the later changes as unsaved; publishing waits for another save.

Validation messages appear beside the affected fields and in the issues drawer.
A blocked save explains the first issue; **Show** opens its participant and tab.
The backend independently validates every save and publish. Credential or service
failures link to the tenant's Services page. A failed request keeps the current
source; **Retry** uses the current draft. A conflict offers to reload the latest
saved revision after confirming that unsaved changes can be discarded.

**JSON** in the header opens the entire call spec for viewing, editing, copying or downloading.
The **JSON** toggle in each participant sidebar header edits just that participant.
Use these editors for advanced model `options` and `provider_options`; the model
forms contain provider, model and voice controls.

**Apply JSON** validates the edit and updates the local draft. **Discard JSON changes**
restores the current source. Apply does not save a revision; use **Save as draft** afterwards.
Unapplied JSON survives closing its view or switching participants. **Review JSON edits**
returns to pending edits, and saving stays disabled until they are applied or discarded.
If another edit changes the same source, the JSON editor asks you to copy your work
and reload the current source before applying it, preventing an overwrite.
The graph is a projection of the source, so a no-op save preserves its meaning and digest.
Large integer values in enums, schema bounds and provider options retain their
exact digits when edited, saved or exported. They remain JSON numbers.
The editor does not store canvas positions or silently migrate older schemas.
Sources using schema `20260915.01` open read-only.

Add `?revision=N` to an existing spec's URL to inspect that immutable revision.
**Continue editing latest revision** opens the current source. This does not copy
an older revision over newer work. Browser Back/Forward and in-app departures ask
before discarding edits or an in-flight write. Reloading or closing the document
uses the browser's own unsaved-changes confirmation. If a session expires during
a write, the editor keeps the source in the tab and disables authoring; copy or
download it before leaving to sign in again.

## Operator API

These endpoints require the existing installation-operator session. Writes also
require the Console CSRF token. Responses are private and not cached.

| Method and path under `/admin/api/tenants/:tenant_key` | Result |
| --- | --- |
| `GET /call-specs/:id` | Latest saved source and revision/publication metadata |
| `GET /call-specs/:id?revision=N` | Requested immutable revision and current publication metadata |
| `POST /call-specs` with `{ "source": ... }` | New spec, revision 1 |
| `PUT /call-specs/:id` with `{ "source": ... }` | Append an immutable revision |
| `POST /call-specs/:id/revisions/:revision/publish` with `{}` | Publish the specified saved revision |
| `GET /call-spec-editor-lookups` | Effective credential names, telephony services and MCP integration names |
| `GET /providers?capability=...` | Installed providers and credential availability |
| `GET /providers/:provider/models?capability=...` | Public models, recommended defaults and voice descriptors |

Read/write responses wrap a `call_spec` object. It includes `call_spec_id`,
`revision`, `schema_version`, `source`, `source_digest`, `published`,
`published_at`, `validation_errors` and participant `routes`. Reads additionally
include `latest_revision` and `published_revision`. Error responses use
`{ "error": { "code": ..., "path": [...], "reason": ... } }` when a field path
and safe reason are available. Another tenant's spec ID is not found. Lookups
never return credential values or perform remote MCP tool discovery; MCP tool
names remain explicit text fields.
