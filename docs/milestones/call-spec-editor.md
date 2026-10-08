# Call spec editor

Status: specification proposed 2026-10-08; not implemented. Design review pending.
Prerequisites: [Tenant Call Specs and API-key administration](tenant-call-specs-and-api-keys.md),
[Operator login and admin dashboard](operator-login-and-admin-dashboard.md),
[Operator admin Storybook](operator-admin-storybook.md) and the
[call direction schema](../call-spec-direction.md).
Sources: the earlier Callpipe flow editor (`ui/src/workspace/pages/flow-editor/` and
`docs/specs/page-flow-editor.md` in the Callpipe repository), the
[call-spec design](../../labnotes/20260905-0405-call-definition-design.md),
[Console React routing](../console-react-routing.md),
[React styling contract](../react-component-styling.md),
[operator API-key authoring](../operator-api-key-authoring.md) and the
[review labnote](../../labnotes/20261008-0721-call-spec-editor-review.md).

## Runnable outcome

An installation operator opens a tenant's Call Specs page in `/admin`, creates a new call spec or
opens an existing revision, edits it on a participant canvas with a side inspector, sees
validation as they edit plus the server's field-level errors, saves a new immutable draft revision and publishes it.
The saved source is the same portable JSON that the tenant API accepts, so a spec authored in the
Console can be exported, reviewed and re-submitted through `/api/tenants/:tenant_key/call-specs`
without translation, and a spec authored through the API opens in the editor without loss.

Today the Console only lists call specs (`TenantCallSpecsPage`); authoring requires the API or the
`mix vxpipe.call_spec.*` tasks.

## What carries over from Callpipe

Callpipe's editor was designed around the same product idea (participants that hand a call to one
another) and most of its interaction design is reusable. Its data model is not: Callpipe edits a
mutable node/edge graph that compiles to runtime profiles, whereas a Vxpipe call spec is a validated
portable document with immutable revisions. The table maps each Callpipe concept to the current
schema (`20261004.01`).

| Callpipe concept | Vxpipe call spec | Decision |
| --- | --- | --- |
| Flow, draft, publish, name dialog | Call spec, immutable revision, explicit publish, `name` (max 256) | Reuse header, name dialog, save/publish buttons. "Save draft" appends a revision; there is no mutable draft. |
| Start/Inbound node, number pool | `incoming_call` / `outgoing_call` block plus the caller/callee human participant and its `connection` | Reuse as a locked **Entry** node. Add a direction switch and outgoing `ring_timeout_ms`. |
| Recording disclosure message | `opening_audio` (`text` with `text_to_speech`, or `file_url`) and `media_policy.record_audio` | Reuse the toggle and message field, backed by `opening_audio`. |
| Agent node | Participant with `type: "agent"` | Reuse node card and tabbed inspector. |
| Agent system prompt (Lexical) | `prompt` (max 32,768) | Reuse layout; a plain textarea is enough (Callpipe's Lexical editor was plain text only). |
| Human handoff node, phone number | Participant with `type: "human"` and a `dial` phone or `receive` web `connection`, `admission: "transfer"`, `transfer_notice` | Reuse node and phone field. Add service selection, web destinations and `number_from_variable`. |
| Human handoff timing summary | Call-level `transfer_policy.attempt_timeout_ms` (1,000 to 120,000) | Show the one supported timeout; do not show retry, availability check or fallback. |
| Transfer edges and transfer tab | Agent `transfers` allowlist of participant keys | Reuse edge drawing, destination search and edge/destination sync. |
| Collected variables, typed rows, required flag | `call_variables.sections.*.schema` (JSON Schema subset) | Reuse the row editor per section; types map to JSON Schema `type`/`enum`. |
| Variable access grants between agents | Agent `variable_permissions` (`read` or `read`+`write` per section) | Replace per-agent grants with a section × participant permission matrix. |
| Agent tools, connected-service tool modal | Agent `tools` map: `host`, `mcp` (with `integration`) or `platform`, plus `conversation_mode` | Reuse the modal's step pattern (source, then tool, then options). |
| Flow-level settings panel (shown when nothing is selected) | Call-level fields | Reuse as the **Call settings** inspector. |
| Test call modal | None | Not supported. The editor has no test call (user decision, 2026-10-08). |

### Present in Vxpipe but missing from the Callpipe UI

The editor must expose these, since they are part of the approved contract:

- **Direction**: incoming versus outgoing, handler rules (outgoing handler must be an agent;
  incoming may be human), outgoing `ring_timeout_ms` (5,000 to 60,000, default 30,000) and the
  callee number being fixed or supplied by the outgoing request's `to`.
- **Capability selections**: call-level `defaults.capabilities` and per-participant
  `capabilities` for `speech_to_text`, `model_inference`, `text_to_speech`,
  `speech_to_speech` and `output_speech_to_text`, each with `provider`, `model`,
  `credential_name`, `options` and `provider_options`. The inspector shows the inherited default
  and whether a participant overrides it.
- **First message**: `first_message.mode` of `wait_for_input`, `generated` or `fixed` (with
  `text`, max 4,096), showing the direction-dependent default.
- **Participant `description`** (max 1,024) and human `transfer_notice` (max 4,096, the private
  briefing).
- **Transfer history** per agent: `fresh`, `all_spoken`, `last_n_spoken` (with `turns`) or
  `selected`.
- **Wait sounds**: `call_setup`, `transfer_to_agent`, `transfer_to_human` and `transfer_joining`,
  each built-in default, an HTTP(S) URL or explicit silence.
- **Media policy**: call-level `audio_routes`, `transcript_routes`, `record_audio` and
  `save_transcripts`, plus per-participant `while_present` overrides that inherit by default.
- **Tool visibility**: default `hidden`, `metadata` or `full`, with per-participant
  `tool_visibility_overrides`.
- **Limits**: `limits.max_duration_ms`.
- **Tool conversation mode**: `blocking` or `non_blocking` per tool, and rejection of reserved
  platform tool names (`transfer`, `read_variables`, `update_variables`, `update_variable`).
- **Dial destination from a variable**: `connection.number_from_variable` (section and
  variable) for transfer destinations, never for the outgoing callee.

### Present in Callpipe but not in the Vxpipe schema

These are not part of this milestone. Each would need its own approved schema change before the UI
could offer it. The editor must not store them in hidden editor-only fields.

- End nodes and terminal outcomes (completed, needs review, abandoned) for analytics.
- Knowledge sources and file grants.
- A shared "common system prompt" prepended to every agent.
- Per-destination transfer instructions (Callpipe stored "when should this agent transfer here?"
  on each edge). The closest current field is the destination's own `description`, which applies
  to every source.
- An "any node" transfer destination.
- Transfer acceptance gates (required variables, warn or block when missing).
- Human handoff availability check, retry count, backup destination and unavailable fallback.
- Sensitive variables with retention periods.
- Chat flows, WhatsApp channel, conversation starters, workspaces, multi-language UI strings,
  flow metrics on the list, pause/archive/duplicate and version history browsing.

The user approved four of these as later schema milestones: a shared prompt, per-destination
transfer instructions, transfer acceptance gates, and human handoff availability check, retry and
fallback. Chat and WhatsApp flows are excluded. None of them is a requirement here.

## Contracts

- **The source document is the editor state.** The editor holds the portable call spec JSON and
  renders the canvas as a projection of it. Saving sends exactly that document. Opening an
  API-authored revision and saving it without edits must produce a source with the same digest.
- **No layout in the source.** Node positions are computed by a deterministic layout (entry node
  first, then agents, then human destinations, ordered by `transfers`). Positions are not
  persisted in v1, so the portable source carries no editor metadata. Manual dragging is
  session-only.
- **Graph rules come from the schema.** Edges can only start at agent participants and represent
  `transfers` entries. The entry edge is the direction block's `handled_by`. A participant key is
  the spec-local identifier; renaming a participant rewrites every reference (`handled_by`,
  `caller`/`callee`, `transfers`, route maps, overrides) in one edit.
- **Validation on both sides.** The UI validates as the operator edits (required fields, lengths,
  numeric ranges, E.164 numbers, identifier format, reference integrity such as `handled_by` and
  transfer targets, direction rules) and blocks save or publish while its own errors remain. The
  backend independently validates every save and publish with `Vxpipe.CallEngine.CallSpec.new/2`
  and is authoritative. The UI also shows backend errors: save and publish return each error's
  JSON path and reason, and the editor marks the matching field, tab and node. A backend error the
  UI cannot map to a field is shown in the validation drawer, never dropped.
- **The save API validates and explains.** The tenant API's save and publish (`POST`/`PUT
  /call-specs`, `.../publish`) stop collapsing failures to a bare `invalid_call_spec`. A rejected
  source returns `422` with the error `code`, the JSON `path` of the offending field and a
  human-readable `reason`, taken from the `Vxpipe.CallEngine.Error` details the validator already
  produces. Service, credential and caller-ID failures keep their existing specific codes and gain
  the path where one exists. Because save itself validates, there is no separate validate
  endpoint. The same error projection serves the Console and the API.
- **One error at a time in v1.** `CallSpec.new/2` stops at the first failure, so a response
  carries that one error. Returning every error would need the validator rewritten to accumulate,
  which this milestone does not do; the UI's own validation catches most mistakes before saving.
- **Console admin endpoints mirror the API.** The editor uses installation-operator
  `/admin/api/tenants/:tenant_key/...` endpoints in Console, calling the same `Vxpipe.Calls`
  workflows with `InstallationOperator.authority()`. Console must not query Persistence directly.
- **Errors never echo secrets.** Validation responses carry paths, reason text and codes; they
  never contain credential values, signed URLs or provider payloads. Credential selection is by
  `credential_name` only.
- **Pickers list only what the runtime accepts.** A model offered in a picker must be one that
  saving and the runtime will accept, so each list comes from the same source the runtime checks:
  - Providers: `Vxpipe.Providers.Registry.catalog/0`, filtered by capability.
  - LLM models: the `llm_db` snapshot already used by ReqLLM (it is packaged models.dev data),
    filtered to models with text output and tool calling, plus the explicit runtime overrides in
    `Vxpipe.AgentRuntime.ProviderSelection` for models newer than the snapshot (for example
    `deepseek-flash`, `gpt-6-luna`). The runtime resolves models through `ReqLLM.model/1`, which
    reads the same snapshot, so a live models.dev fetch would list models the runtime then
    rejects. New models arrive by updating the `llm_db` dependency or adding an override.
  - Audio and speech-to-speech models: part of the speech provider contract. The
    `Vxpipe.CallEngine.Speech.STTProvider`, `TTSProvider` and `STSProvider` behaviours gain a
    `models/0` callback returning the adapter's supported models, each with an ID, display name,
    whether it is the default, and its voices (a known list with a default voice, or free text
    with the default shown). Registering a provider capability in
    `Vxpipe.Providers.Registry` therefore also declares its models; an adapter without
    `models/0` fails `mix compile --warnings-as-errors`. Each adapter's `configure/1` checks the
    requested model against its own `models/0`, replacing today's private lists (for example
    `@models` in the Cartesia and ElevenLabs TTS modules, Deepgram Flux models and the fixed
    Google and GPT-Live models), so validation and listing cannot drift. The listing resolves
    each capability with `Registry.resolve_capability/2`, so providers whose implementation
    application is not installed are omitted rather than listed.
  - Voices: listed where the adapter declares a known set; otherwise free text (Deepgram Flux
    validates the voice token's format only).
  - LLM models use the same descriptor shape (ID, display name, default flag). Their listing lives
    in `vxpipe_agent_runtime`, which owns ReqLLM and `llm_db`, beside the overrides in
    `ProviderSelection`, so `vxpipe_providers` gains no `llm_db` dependency.
- **Every provider has one recommended default.** Each speech adapter's `models/0` marks exactly
  one default model, and each model with a voice list marks one default voice. Each LLM provider
  declares one default model, and that model must resolve through `ProviderSelection`. Today these
  defaults exist only in the frontend's `setupCatalog.json` (`defaultModels`, for example
  `deepgram` STT `flux-general-multi`, `cartesia` TTS `sonic-3.6`, `google` LLM
  `gemini-2.5-flash`, `openai` STS `gpt-live-1`). This milestone moves them into the backend
  declarations with the same values, has the listing return them, and removes `defaultModels`
  from `setupCatalog.json` so the onboarding display reads them from the listing instead.
- **Pickers preselect the default.** Choosing a provider selects its default model and default
  voice, marked "Recommended" in the list. Switching provider resets the model and voice to the
  new provider's defaults. A new call spec starts with defaults for each capability it needs.
  Opening an existing spec never replaces a model or voice it already names.
  - Credential names from the tenant's service bindings, telephony services from the tenant
    telephony applications, MCP integrations from the configured integration list.

## Specification

### Routes and pages

- `/admin/tenants/:tenantKey/call-specs/new` opens an empty editor seeded with an incoming web
  caller and one agent, matching `examples/call-specs/development.json`.
- `/admin/tenants/:tenantKey/call-specs/:callSpecId` opens the latest revision;
  `?revision=N` opens a specific one read-only, with an action to continue editing from it.
- The Call Specs list gains a **New call spec** action and row links into the editor.
- Leaving with unsaved changes asks for confirmation.

### Layout (from Callpipe)

- Floating header: back link, editable name, revision and published badges, validation state,
  **Save draft** and **Publish**. Publish is enabled only for a saved revision with no
  validation errors.
- Canvas with a toolbar to add an agent or a human destination, and an **Arrange** action.
- Right inspector (about 34rem, full width on narrow screens):
  - Nothing selected: **Call settings** with tabs Direction, Defaults (capabilities), Variables,
    Media and recording, Wait sounds, Advanced (tool visibility, limits, transfer timeout).
  - Entry node: caller or callee connection, opening audio, ring timeout for outgoing calls.
  - Agent: tabs Prompt (prompt, description, first message), Voice and model (capability
    overrides), Variables (section permissions), Transfers (destinations, transfer history),
    Tools, Presence (`while_present`).
  - Human destination: name/key, description, connection (web or phone service, fixed number or
    from variable), private briefing, capability and presence overrides.
  - Selected edge: source, target, delete.
- Validation drawer listing every server error with a link that selects the node and tab.
- **Source** view: read-only formatted JSON with copy and download, so operators can move a spec
  to the API. Editing raw JSON is out of scope for v1.

### Backend additions (Console and Calls)

- `GET /admin/api/tenants/:tenant_key/call-specs/:id[?revision=N]`: source, revision metadata,
  published state and routes.
- `POST /admin/api/tenants/:tenant_key/call-specs` and `PUT .../:id`: save a revision.
- `POST .../:id/revisions/:revision/publish`: publish.
- `GET /api/tenants/:tenant_key/providers?capability=...` and the Console mirror
  `GET /admin/api/tenants/:tenant_key/providers`: provider IDs, display names, capabilities and
  whether the tenant has a usable credential for each.
- `GET /api/tenants/:tenant_key/providers/:provider/models?capability=...` and its Console
  mirror: model IDs, display names, and for LLMs the context limit and tool support from
  `llm_db`; for TTS/STS the known voices. Responses are built from in-memory catalogs and make no
  provider network calls.
- Console-only lookups for credential names per provider, telephony services and MCP integrations
  with their tools, without secret material.
- Save and publish failures on both the tenant API and the Console return `code`, `path` and
  `reason`, so the UI can place them on fields.

### Frontend

- Components live under Console assets (`apps/vxpipe_console/assets/src/admin/callSpecEditor/`),
  not in `@vxpipe/react`.
- Add `@xyflow/react` to the Console assets package (Callpipe used it for the same canvas). No
  Lexical dependency.
- Pure functions own source edits (add/rename/remove participant, add/remove transfer, set
  capability override, set section permission) and are unit tested without React.
- Storybook first, as for the [operator admin Storybook](operator-admin-storybook.md): page and
  inspector stories with fixtures for default, loading, empty new spec, validation errors, save
  failure, published revision, outgoing call, narrow viewport and long content. Production wiring
  follows the user's review of those stories.

## Implementation checklist

- [ ] A. Source model: red unit tests, then pure edit functions, client validation rules and the
  graph projection for both directions, including participant renaming and round-trip with the
  three files under `examples/call-specs/`.
- [ ] B. Storybook: header, canvas, every inspector and the validation drawer with deterministic
  fixtures; record the user's review.
- [ ] C. Structured save/publish errors on the tenant API (red Gateway tests for path and reason on
  representative failures), then Console read, save and publish endpoints sharing that projection,
  including tenant isolation and no secret material. Update the API guide's error table.
- [ ] D. Provider and model listing: add `models/0` to the STT, TTS and STS provider behaviours,
  implement it in every registered adapter and make each `configure/1` validate against it,
  with a contract test that iterates the registry so a newly registered provider is covered
  automatically; move the default models from `setupCatalog.json` into the backend declarations; LLM listing from `llm_db` plus runtime overrides; tenant API and
  Console endpoints; Console lookups for credentials, telephony services and MCP integrations.
- [ ] E. Production integration: routes, list actions, unsaved-change guard, save and publish
  through the real endpoints.
- [ ] F. Documentation: Console authoring section in
  [operator API-key authoring](../operator-api-key-authoring.md) or a new operator guide, and this
  milestone's evidence.

## Acceptance and failure checks

- [ ] Create an incoming web spec in the editor, save, publish and start a sample call through its
  published route.
- [ ] Create an outgoing spec; the UI flags a human handler, a callee with
  `number_from_variable` and an out-of-range ring timeout before saving.
- [ ] Saving an invalid source through the tenant API returns `422` with the failing field's path
  and reason instead of a bare `invalid_call_spec`.
- [ ] Every LLM model the listing returns for a provider resolves through the runtime's provider
  selection.
- [ ] Choosing a provider in the editor preselects its recommended model and voice; switching
  provider resets them; opening an existing spec keeps its saved choices.
- [ ] Every LLM provider's declared default resolves through `ProviderSelection`, and the
  onboarding page shows the same defaults it showed before, now read from the listing.
- [ ] For every speech capability in the registry, `models/0` is non-empty, has exactly one
  default, and `configure/1` accepts each listed model with its default voice and rejects an
  unlisted model.
- [ ] With client validation bypassed in a test, the same invalid source is rejected by the
  backend and its errors appear on the matching fields.
- [ ] Open each example under `examples/call-specs/` and save without edits; the saved source
  digest equals the original.
- [ ] A spec saved through the tenant API opens in the editor and every field it uses is visible.
- [ ] Renaming a participant updates all references; the saved spec validates.
- [ ] A backend validation error selects the right node and tab and highlights the field; an
  unmappable backend error appears in the validation drawer.
- [ ] Saving after an edit creates revision N+1 and leaves revision N unchanged and still published.
- [ ] Another tenant's spec ID returns not found; responses contain no credential values.
- [ ] Rendered browser inspection with `agent-browser` at desktop and phone widths for list, new,
  edit, validation-error, outgoing and published states.

## Decisions and open questions

Decided 2026-10-08:

- No test calls from the editor.
- The UI validates on its own and also shows the backend's validation errors on the matching
  fields. The backend validates independently and is authoritative.
- The tenant API's save and publish return specific errors with field paths; no separate validate
  endpoint.
- Add provider and model listing endpoints. LLM models come from the `llm_db` snapshot (models.dev
  data already bundled with ReqLLM) rather than a live models.dev fetch, because the runtime
  resolves models through that same snapshot.

- Every provider has a recommended default model (and voice), preselected in the pickers.
- Approved follow-ups, each a separate schema milestone after this one and not part of it: a
  shared prompt for all agents, per-destination transfer instructions, required variables before
  a transfer, and human handoff availability check, retry and fallback. Chat and WhatsApp flows
  are excluded.

Open:

1. **Layout persistence.** Deterministic layout is assumed. If operators need saved positions, store
   them in Console-owned metadata keyed by spec and revision, never in the source.

## Scope boundaries

No test calls, no validator rewrite to report multiple errors, no live models.dev fetch, no schema changes, no new runtime behavior, no raw JSON editing, no revision history browser beyond
opening a revision by number, no tenant-user (non-operator) access and no tenant API changes beyond structured
save/publish errors and the provider/model listings.

## Specification review

Pending. Review for missing contracts and dependency order before implementation starts.
