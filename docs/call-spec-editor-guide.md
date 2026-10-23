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
policies. On a phone, these controls open in a side sheet.

The header uses adjoining **Publish** and ellipsis cells separated by vertical
dividers, with hover backgrounds filling the toolbar height without inset padding
or gaps. **JSON editor** is available inside the ellipsis menu. Issue controls use the same treatment.

A subtly shaded second row in the top toolbar places **Add AI Agent**, **Add Human**,
and the **Arrange nodes** icon on the left, with **Call settings** on the right.
Hover or focus these icons to see their names; Call settings retains its
validation issue badge.

Human and Entry inspectors use compact **Connection** cards: **Web** shows WebRTC,
and **Phone** shows its provider and number. Phone opens a provider modal; incoming
Entry also searches existing account numbers and disables numbers assigned to
another published spec. Outgoing and transfer connections retain destination
fields. Switching to Web clears phone details. See [phone connection selection](phone-connection-picker.md)
for provider adapters, pagination and publish conflict rules.

Model and voice choices
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
Audio and transcript routing are configured in each participant’s **Media** tab.
**Call settings → Media** contains only recording and transcript-saving permissions.
Existing call-wide routing values are preserved in JSON.

**Advanced** exposes one call-wide tool visibility setting. Per-agent and per-tool
visibility controls are not shown; existing overrides remain in the saved JSON.

Dropdowns show concrete runtime choices instead of a separate **Default** item:
call-wide permissions start at **Allow**, transfer history at **Fresh**, tool
visibility at **Hidden**, and tools at **Blocking**.
Wait sounds show **Phone ring** for call setup and human transfers, and
**Cafe bossa** for agent transfers and joining. Opening these panels leaves
omitted settings unchanged in the JSON.

Each wait-sound row keeps its label, sound selector, and preview control aligned.
Choose **Audio URL** to enter a link in a modal; **Use audio** applies the link,
while Cancel or Close keeps the previous selection. The pencil edits a saved URL.
Preview built-in or custom audio with Play; Silence has no playback. Only one
preview plays at a time, and leaving the panel stops it. Pause keeps your place;
Resume continues from there. The blue playback control has a shrinking ring that
shows the remaining audio without a time label. Loading uses a separate indicator,
and reduced-motion preferences disable the spinner and ring interpolation.

Participant model selectors show their inherited provider and model directly.
Selecting the call-wide provider or its model restores inheritance. If no model
is configured, optional capabilities show **Not configured**; required ones
prompt for a provider. Participant media policies retain **Inherit** because
these policies combine with call-wide restrictions while the participant is
present.

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

**Add variable** and a row's edit button open the same compact modal. **Name**
and **Type** each share a row with their control. **Required?** and **Enum?** each have their own label-first row. Name, Type,
and Valid values place labels beside inputs on desktop and above them on mobile. Enabling Enum shows **Valid values**: type a value and press Enter to
add a tag, or use its × button to remove it. Each value uses the field's type;
numbers and booleans are stored as those types, not as strings. Duplicate values
are rejected. Nested object fields and array items use the same controls.

Constraints and nullable controls are omitted. Existing constraints remain in
JSON and can be edited there. Variables accept null by default on the backend,
including enums; section roots remain objects. Advanced JSON authors can set
`nullable: false` on a variable to retain strict null rejection. Changes
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

**Agent settings → Tools → Add tool** opens a searchable list grouped into
built-in tools, registered host tools (when available), and MCP integrations.
The first screen lists MCP names, not their individual tools. Selecting an MCP
opens its searchable checklist. Check individual tools or **Include all tools**,
then add the selection together. Include all captures the currently available
tools, including those hidden by search; it saves each name explicitly and never
saves a wildcard. Tools added to the MCP later remain excluded. Already enabled
tools are marked **Added** and stay enabled when the new selection is cleared.

Each selected MCP tool has its own **Non-blocking** checkbox. Unchecked means
blocking: the conversation waits for the result. Checked lets the conversation
continue while that tool runs. There is no shared mode control in the checklist.
Built-in and host tools go directly to their individual options.
Cancel discards the selection. Both lists scroll inside a modal whose dimensions
stay stable between screens. On short screens, the options area can also scroll
while the footer remains available.

MCP entries in the picker show the integration name and available tool count
on one line, for example `calendar (18)`.

New tools use their registered names, without a separate editable alias:
built-in and host names remain unchanged, and MCP names use
`<integration>__<tool>`, for example `calendar__find_slots`. No `mcp__` prefix
is needed: the integration already identifies the source. The add-tool modal
shows the original tool names; after saving, the agent's enabled-tools list shows
the qualified name to use in prompts. The
[MCP protocol recommends names unique within a server](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#tool-names)
but does not prescribe a cross-server prefix. Double underscores also fit the
installed ReqLLM function-name rules, which exclude dots. New MCP registrations
must fit ReqLLM's 64-character combined-name limit and start with a letter or
underscore; later characters may be letters, digits, underscores, or single
hyphens between segments. The editor rejects incompatible names and collisions
instead of shortening names or adding unpredictable suffixes. The compiler
exposes the qualified name to the model and retains the original tool name when
calling the MCP server.

The enabled-tools list shows each source and registered name on one row, with
edit and delete controls on the right. A clock icon beside a blocking tool has a
**Blocking** tooltip, available on hover or keyboard focus. Non-blocking tools
have no clock icon.

**Edit tool** opens a compact dialog that changes only the conversation mode.
For MCP tools, its description uses `calendar · find_slots` to identify the
integration and original tool name.
It preserves the saved name, tool selection and visibility overrides; replacing
a tool requires removing it and adding another. Existing saved aliases are not
silently migrated, avoiding broken prompt references. Tools missing from the
current catalog still allow conversation-mode edits.

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

**JSON editor** in the header ellipsis menu opens the entire call spec for viewing,
editing, copying or downloading.
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
| `GET /call-spec-editor-lookups` | Effective credential names, telephony services, MCP integration names and available tool descriptors |
| `GET /providers?capability=...` | Installed providers and credential availability |
| `GET /providers/:provider/models?capability=...` | Public models, recommended defaults and voice descriptors |

Read/write responses wrap a `call_spec` object. It includes `call_spec_id`,
`revision`, `schema_version`, `source`, `source_digest`, `published`,
`published_at`, `validation_errors` and participant `routes`. Reads additionally
include `latest_revision` and `published_revision`. Error responses use
`{ "error": { "code": ..., "path": [...], "reason": ... } }` when a field path
and safe reason are available. Another tenant's spec ID is not found. Lookups
never return credential values or perform remote MCP tool discovery. The
`tool_catalog` contains `tools` (type, tool name, description and, for MCP tools,
integration name) and `mcp_available`. MCP choices come from the published
catalog snapshot, respecting tenant overrides, allowed tools and supported input
schemas. An unavailable MCP store leaves built-in and registered host tools
usable, with an explicit unavailable state for MCPs.

## Timing inputs and Entry identity

Call duration, transfer attempt timeout, and outgoing ring timeout use seconds in
form controls, including fractional values such as `25.6`. Saved call-spec JSON
and API requests keep integer milliseconds (`25600`); input is rounded to the
nearest millisecond. Blank optional inputs use the existing runtime defaults.

New UI-created incoming and outgoing specs use `caller` as the Entry participant
key. Entry settings do not expose a key editor. Existing/imported keys are
preserved; the full JSON editor remains available for source-level edits.
