# Call spec editor

Status: implementation started 2026-10-08; checkpoints V, P and L complete; K is next. Design review complete.
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
- **Provider model IDs may have a public abstraction.** User clarification 2026-10-08:
  list Deepgram TTS as `flux` with a separate free-text voice and let the adapter
  construct `flux-{voice}-en`. The runtime already accepts `model: "flux"` with
  `options.voice`; use that public shape for new editor selections. Preserve existing
  combined IDs without rewriting saved source. The catalog descriptor carries any
  adapter-owned voice parameter mapping, so future combined-ID providers follow the
  same contract. For Flux, the recommended combination remains voice `hannah` (the
  prior onboarding default `flux-hannah-en`). Reject unknown public models while
  retaining the adapter's supported legacy concrete IDs.
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
    telephony applications, MCP integration names from the configured integration list.

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
- Issues list (drawer) and toasts as defined in [Error presentation](#error-presentation).
- **Source** view: read-only formatted JSON with copy and download, so operators can move a spec
  to the API. Editing raw JSON is out of scope for v1.

### Error presentation

The editor is too dense to show every error everywhere. Each action therefore ends with exactly
one toast saying what happened, and the toast's **Show** action takes the operator to the field
when there is one. Inline messages appear only where the operator is already looking.

**Surfaces**

| Surface | Shows | Never shows |
| --- | --- | --- |
| Toast | The outcome of every save and publish (success or failure), and failures of other user actions. One toast per action; a new save or publish replaces the previous action's toast. Success toasts auto-dismiss; failure toasts stay until dismissed. | Client validation while editing. |
| Inline field message | The client or backend error for a field in the currently open node and tab. | Errors for fields that are not on screen. |
| Badges | An error count on each canvas node, on the Call settings entry and on each inspector tab, so the operator can find errors without a list. | Messages. |
| Header issue count | "N issues" when client validation finds problems; clicking opens the issues list. | Backend or network failures. |
| Issues list (drawer) | Every current client error plus the last backend validation error, each with **Show**. Opened on demand, never automatically. | Success, network or permission failures. |
| Page error state | Failures to load the spec or the catalog, with **Retry**. These are not toasts, because there is no editor to return to. | Save and publish failures. |

**Rules**

- Client validation runs on every edit and updates badges, the issue count and visible inline
  messages. It never raises a toast by itself.
- Saving or publishing with client errors does not call the backend. It shows one toast:
  "Fix N issues before saving" (or publishing) with **Show first issue**.
- The **Show** action selects the node (or Call settings), opens the tab, scrolls to the field and
  focuses it. A path the editor cannot place opens the issues list instead.
- A backend validation error stays inline on its field and in the issues list until that field is
  edited or the next save succeeds.
- The editor never discards unsaved changes because of a failure. Retryable failures offer
  **Retry** in the toast.
- Toast text names the location in operator terms ("Agent assistant › Prompt") and the problem in
  plain words, using a client message catalog keyed by error code and path pattern. Paths the
  catalog does not cover fall back to the location and the backend's `reason`.

**Save and publish outcomes**

| Outcome (status, code) | Toast | Also |
| --- | --- | --- |
| `201` save | "Saved as revision N" | Header shows the new revision. |
| `200` publish | "Published revision N" | Header shows published. |
| Client errors present (no request) | "Fix N issues before saving" (or publishing), **Show first issue** | Badges and issue count already visible. |
| `422 invalid_call_spec` with a mappable path | "Couldn't save: Agent assistant › Prompt is required", **Show** | Inline on the field; node and tab badges. |
| `422 invalid_call_spec` with an unmappable path | "Couldn't save: {reason}", **Show** opens the issues list | Listed in the issues list. |
| `409 call_spec_not_publishable` | "Couldn't publish: {first error}", **Show** | Same placement as a validation error. |
| `422 provider_credential_unavailable` | "No usable {provider} credential for this tenant", **Open services** | Inline on the capability picker when the path names it. |
| `403 provider_service_forbidden` | "This tenant can't use {provider}", **Open services** | Inline on the capability picker when the path names it. |
| `422 telephony_caller_id_missing` | "{service} has no outbound caller ID number", **Open services** | Inline on the callee connection. |
| `422 invalid_telephony_route` | "Phone number {field} isn't routable through {service}", **Show** | Inline on the connection. |
| `422 private_call_spec_material` | "Remove credentials or secrets from {location}", **Show** | Inline on the field; the value is never echoed. |
| `409 revision_conflict` | "This spec changed while saving. Reload to see the latest revision", **Reload** | Unsaved changes kept until the operator reloads. |
| `404 call_spec_not_found` | "This call spec no longer exists" | Save disabled. |
| `403 authoring_forbidden` | "You don't have permission to change call specs" | Save and publish disabled. |
| `401` or expired operator session | Existing Console session-expiry behavior; the toast says changes in this tab are kept until the page is left. | — |
| `400 invalid_request` | "Couldn't save: the editor sent an invalid request" | Logged as a client defect; no field placement. |
| `503 call_spec_authoring_unavailable`, network error or timeout | "Couldn't save. Try again", **Retry** | — |

Copy in this table is the intended meaning; final wording is settled in Storybook review.

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
- Console-only lookups for credential names per provider, telephony services and MCP integration
  names, without secret material. MCP tool names are free text in v1.
- Save and publish failures on both the tenant API and the Console return `code`, `path` and
  `reason`, so the UI can place them on fields.

### Frontend

- Components live under Console assets (`apps/vxpipe_console/assets/src/admin/callSpecEditor/`),
  not in `@vxpipe/react`.
- Add `@xyflow/react` to the Console assets package (Callpipe used it for the same canvas). No
  Lexical dependency.
- **Standard shadcn components first.** Every control uses a standard shadcn registry
  component when one fits, installed with the shadcn CLI so the source matches the registry.
  Project components are compositions of those (inspector panels, node cards, pickers), not
  replacements for them. Expected set: `button`, `input`, `textarea`, `label`, `field`,
  `select`, `combobox` (`popover` + `command`), `switch`, `checkbox`, `radio-group`,
  `toggle-group`, `tabs`, `dialog`, `alert-dialog` (unsaved changes, delete participant),
  `sheet` (inspector on narrow screens), `dropdown-menu`, `tooltip`, `badge`, `separator`,
  `scroll-area`, `collapsible`, `item`, `skeleton`, `table` (section permission matrix) and
  `sonner` or the existing `PageToast` for save and publish feedback. A custom control needs a
  short note in the labnote saying which shadcn component was considered and why it did not fit.
  Existing Console pages keep their current `Button` in this milestone; aligning them is a
  separate change.
- **Copy and adapt Callpipe's components; do not redesign them.** Callpipe's flow editor already
  has presentational components and Storybook stories in `ui/src/workspace/pages/flow-editor/`
  (`editor-header`, `editor-toolbar`, `flow-canvas`, `flow-node`, `flow-layout`,
  `inspector-primitives`, `inspector`, `agent-inspector`, `human-inspector`, `inbound-inspector`,
  `flow-level-inspector`, `selected-edge-inspector`, `generic-node-inspector`, `display-helpers`)
  plus `components.stories.jsx` and `flow_editor.stories.jsx`. Both stacks use Tailwind v4,
  shadcn-style Radix primitives, class-variance-authority, cmdk and lucide. Adapting each copied
  file means:
  - converting JSX to strict TypeScript;
  - replacing `t("flowEditor...")` calls with English strings, since Console has no i18n;
  - binding props to the call spec source and S's edit functions instead of Callpipe node data
    (`data.systemPrompt`, `variableAccess`, `transfers.allowedDestinations`);
  - importing standard shadcn components installed in Console (U1) in place of Callpipe's local
    `@/components/ui/*` copies, and replacing hand-built controls in the copied files (native
    `<select>`, custom tab buttons, ad hoc popovers) with their shadcn equivalents;
  - checking lucide icon names, since Callpipe uses lucide 0.468 and Console 1.46;
  - replacing hard-coded light-only colors (`bg-slate-100`, `text-slate-950`, `border-slate-200`
    and similar) with semantic shadcn tokens so the dark default theme works;
  - moving stories to the Console admin Storybook conventions and call spec fixtures.
- **Not copied:** `use-flow-editor-controller.js`, `flow-definition.js` and `api.js` (replaced by
  S and W), the test call modal and its controller, `variable-retention-control`, channels,
  WhatsApp and conversation starters, knowledge pickers, the Lexical `prompt-editor` and the
  "any node" transfer option. Panels with no Callpipe counterpart (Defaults and Voice and model
  pickers, Media and recording, Wait sounds, Advanced, first message, transfer history, Presence)
  are new and built from the same copied primitives.
- Pure functions own source edits (add/rename/remove participant, add/remove transfer, set
  capability override, set section permission) and are unit tested without React.
- Storybook first, as for the [operator admin Storybook](operator-admin-storybook.md): page and
  inspector stories with fixtures for default, loading, empty new spec, validation errors, save
  failure, published revision, outgoing call, narrow viewport and long content. Production wiring
  follows the user's review of those stories.

## Delivery strategy

Implement **V → P → L → K → S → U → C → W → Z** in that order. The four backend checkpoints
(V, P, L, K) settle the contracts the editor depends on: error shape, model declarations and
listing responses. S builds the editor's source model as pure TypeScript. U puts the whole editor
in Storybook and stops for the user's review. C and W connect it to real endpoints only after that
review. Z closes the milestone. S and U depend only on the response shapes fixed in V and K, so
they may start once those shapes are committed.

For each checkpoint: write the smallest red test in the owning child for the stated behavior,
make it green, then refactor; update the relevant docs and this milestone's labnote. Run the
broader relevant suite and all five root gates before treating the checkpoint as usable. Each
checkpoint is one coherent commit; none is committed as complete while its exit gate is red.
Proposed file names may be refined without changing the contracts or exit gates.

Dependency direction for the catalog follows `mix.exs`: Call Engine (which already depends on
Agent Runtime and Providers) exposes the combined model catalog; Calls adds tenant credential
availability; Gateway and Console call Calls. Neither Gateway nor Console reads `llm_db` or the
provider registry directly.

| Checkpoint | Runnable slice | Candidate commit subject |
| --- | --- | --- |
| V | Saving or publishing an invalid spec through the tenant API returns the failing field's path and reason. | Return field-level call spec validation errors |
| P | Every registered speech adapter declares its models and recommended default, and validates against them. | Declare speech models in the provider contract |
| L | Each LLM provider lists runnable models from `llm_db` plus runtime overrides, with one default. | List runnable LLM models with recommended defaults |
| K | Tenant API and Console list providers and models; onboarding reads defaults from the listing. | Add provider and model listing endpoints |
| S | Pure source-model functions edit, validate and project any supported call spec without loss. | Add the call spec editor source model |
| U | The complete editor is reviewable in Storybook with fixtures. | Add call spec editor Storybook |
| C | Console can read, save and publish specs and look up credentials, telephony services and MCP integrations. | Add Console call spec authoring endpoints |
| W | Operators create, edit, save and publish call specs in `/admin`. | Integrate the call spec editor in Console |
| Z | Full acceptance, rendered inspection and documentation. | Complete the call spec editor milestone |

## Checkpoint V — Field-level errors on the tenant API

Outcome: `POST`/`PUT /api/tenants/:tenant_key/call-specs` and the publish route return a specific
error for an invalid source instead of a bare `invalid_call_spec`.

- [x] **V1 — Red Gateway tests.** In `apps/vxpipe_gateway/test/vxpipe/gateway/http/call_spec_writes_test.exs`,
  submit representative invalid sources (missing `prompt`, unknown `handled_by`, an outgoing
  human handler, an out-of-range `ring_timeout_ms`, a bad E.164 number, an unknown transfer
  target, a reserved tool name) and expect `422` with `error.code`, `error.path` (a JSON path as
  a list of strings) and `error.reason`. Confirm they fail on the current opaque body.
- [x] **V2 — Shared public projection.** Add one function that turns a
  `Vxpipe.CallEngine.Error` with `details` `path`/`reason` into the public error body, owned by
  Calls so Gateway and Console share it. Keep the existing specific codes
  (`provider_service_forbidden`, `provider_credential_unavailable`,
  `telephony_caller_id_missing`) and add a path where the failure has one.
- [x] **V2b — Specific codes for collapsed failures.** Red tests, then return
  `409 revision_conflict`, `422 invalid_telephony_route` and `422 private_call_spec_material`
  (with paths where available) instead of today's `503` or generic `invalid_call_spec`, as listed
  in [Error presentation](#error-presentation).
- [x] **V3 — Publish failures.** Replace the `unsupported_call_plan` summary in
  `validation_errors` and the unpublishable-draft `409` body with the same code/path/reason
  entries. Red test first.
- [x] **V4 — Safety.** Test that reasons never echo submitted values: a secret-looking prompt,
  URL or number in an invalid field does not appear in the response. `private_data?` rejections
  keep a path and a fixed reason.
- [x] **V5 — Docs.** Update the error table in
  [operator API-key authoring](../operator-api-key-authoring.md) with the new body and an example.
- [x] **Exit V.** Gateway suite, root gates and the existing save/publish/outgoing API tests pass;
  responses carry exactly one error, as the validator is fail-fast.

Checkpoint V evidence (2026-10-08): ten focused Gateway tests and ten Calls workflow
tests pass after confirmed red runs. All five root gates pass. The default umbrella
suite reports 3,326 tests, zero failures and 120 exclusions (seed 947553), including
589 Gateway tests and the existing save/publish/outgoing coverage. No live tests ran.
See the [implementation labnote](../../labnotes/20261008-1528-call-spec-editor.md).

## Checkpoint P — Speech models in the provider contract

Outcome: registering a speech adapter declares its supported models, voices and one recommended
default, and the adapter rejects any model it does not declare.

- [x] **P1 — Red contract test.** Add a Call Engine test that iterates
  `Vxpipe.Providers.Registry` and, for every `:stt`, `:tts` and `:sts` capability, expects a
  non-empty `models/0`, exactly one default model, one default voice for each model with a voice
  list, `configure/1` accepting each listed public model with its default voice, and `configure/1`
  rejecting an unknown model (with the documented legacy Flux concrete-ID compatibility). It fails because `models/0` does not exist.
- [x] **P2 — Behaviour callback.** Add `@callback models() :: [model]` and a small model
  descriptor type (ID, display name, default flag, voices as a list with a default or free text)
  to `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/stt_provider.ex`, `tts_provider.ex`
  and `sts_provider.ex`.
- [x] **P3 — Adapters.** Implement `models/0` in every adapter that implements those behaviours:
  Cartesia, Deepgram, ElevenLabs and Google STT/TTS, Google and GPT-Live STS, Rime TTS, and the
  Morse STT/TTS/STS/duplex sessions under both `providers/morse_code/` and
  `call_engine/provider/morse_code_*`. Move the private lists (`@models` in Cartesia and
  ElevenLabs TTS, Deepgram Flux, fixed Google and GPT-Live models) into `models/0` and have
  `configure/1` check against it. Adapter behavior for currently valid configurations is unchanged.
- [x] **P4 — Defaults.** Set each adapter's default to the value in today's
  `apps/vxpipe_console/assets/src/admin/setupCatalog.json` `defaultModels` (for example Deepgram
  STT `flux-general-multi`, Cartesia TTS `sonic-3.6`, ElevenLabs STT `scribe_v2_realtime`, Google
  STS `gemini-3.8-live`, OpenAI STS `gpt-live-1`). Record any adapter with no frontend default
  and the default chosen for it.
- [x] **Exit P.** The contract test passes for every registered capability, existing adapter and
  room tests are green, and `mix compile --warnings-as-errors` fails if an adapter omits
  `models/0` (checked once by temporarily removing it locally, not committed).

Checkpoint P progress: model declarations and pure acceptance tests pass for all
registered speech capabilities and both Morse namespaces. The 670-test provider,
speech and inline-activation group passes (22 excluded, seed 821225). Removing a
required callback correctly fails warnings-as-errors compilation. All five root gates pass; the full default umbrella suite passes 3,343 tests,
zero failures, 120 excluded (seed 468087). No live tests were run.

## Checkpoint L — Runnable LLM model listing

Outcome: for each LLM provider the runtime supports, Agent Runtime lists models it can actually
run, with one recommended default.

- [x] **L1 — Red tests.** In `apps/vxpipe_agent_runtime/test/vxpipe/agent_runtime/`, expect a
  listing per supported provider (google, openai, deepseek, openrouter, fireworks, zenmux) where
  every entry resolves through `ProviderSelection`, non-chat entries (image or video output, no
  text output) are excluded, the runtime overrides (`deepseek-flash`, `gpt-6-luna`) are included,
  and exactly one entry is the default.
- [x] **L2 — Listing module.** Add an Agent Runtime module that reads the `llm_db` snapshot,
  filters to text output with tool calling, adds the `ProviderSelection` overrides and returns
  the shared descriptor shape (ID, display name, default flag, context limit). Keep the override
  definitions in one place so the listing and `ProviderSelection` cannot drift.
- [x] **L3 — Defaults.** Declare one default per provider, matching `setupCatalog.json`
  (google `gemini-2.5-flash`, openai `gpt-5`, zenmux `openai/gpt-5`, deepseek `deepseek-flash`,
  openrouter `google/gemini-3.5-flash-lite`, fireworks
  `accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b`). A test fails if a default is not
  in the provider's listing.
- [x] **L4 — Load cost.** Measure listing time and memory for the largest provider (openrouter)
  after `LLMDB.load/0`; record it. Cache the filtered result in `:persistent_term` only if the
  measurement justifies it.
- [x] **Exit L.** Agent Runtime suite and root gates pass; the listing makes no network calls.

Checkpoint L progress: all 108 Agent Runtime tests pass (eight excluded, seed
256901). Local OpenRouter measurements and the no-cache decision are recorded in
[the catalog decision](../llm-model-catalog.md). All five root gates pass; the default umbrella suite passes
3,352 tests, zero failures, 120 excluded (seed 226406). No live tests ran.

## Checkpoint K — Provider and model listing endpoints

Outcome: API clients and the Console can list providers per capability and each provider's
models with its recommended default; the onboarding page reads defaults from the backend.

- [ ] **K1 — Red catalog tests.** Add a Call Engine model-catalog facade test combining P's
  speech declarations and L's LLM listing by capability (`speech_to_text`, `text_to_speech`,
  `speech_to_speech`, `output_speech_to_text`, `model_inference`), omitting providers whose
  implementation is not installed (`Registry.resolve_capability/2`).
- [ ] **K2 — Calls workflow.** Add a Calls function that returns the catalog plus whether the
  tenant has a usable credential for each provider (tenant binding or inherited platform
  credential), without credential values. Test tenant isolation.
- [ ] **K3 — Tenant API routes.** Red Gateway tests, then
  `GET /api/tenants/:tenant_key/providers?capability=...` and
  `GET /api/tenants/:tenant_key/providers/:provider/models?capability=...`, authenticated like
  the existing tenant routes. Unknown provider or capability returns `404`/`422`.
- [ ] **K4 — Console routes.** Red endpoint tests, then the matching
  `/admin/api/tenants/:tenant_key/providers...` routes in
  `apps/vxpipe_console/lib/vxpipe/console/router.ex`, with a controller beside
  `AdminCallSpecsController`.
- [ ] **K5 — Onboarding cutover.** Remove `defaultModels` from `setupCatalog.json`; have
  its readers (`setupCatalog.ts` and `OnboardingStory.tsx`) take defaults from the
  listing (fixtures in Storybook). Update `setupCatalog.test.ts`. The rendered onboarding page
  shows the same defaults as before.
- [ ] **K6 — Docs.** Document both tenant API routes and their response shape in the API guide.
- [ ] **Exit K.** Gateway, Console and Calls suites, Console frontend tests and root gates pass;
  onboarding is inspected in a rendered browser with `agent-browser`.

## Checkpoint S — Call spec source model

Outcome: framework-free TypeScript functions hold a call spec source, edit it, validate it on the
client and project it to a graph, round-tripping every supported source without loss.

- [ ] **S1 — Red round-trip tests.** Under `apps/vxpipe_console/assets/src/admin/callSpecEditor/`,
  load each file in `examples/call-specs/` and expect parse → project → serialize to produce an
  identical JSON value. Fails because the module does not exist.
- [ ] **S2 — Types.** Define TypeScript types for schema `20261004.01`: direction blocks,
  participants (human and agent fields), connection, capabilities, first message, tools,
  transfers, transfer history, variable sections and permissions, media policy, wait sounds,
  tool visibility, limits, opening audio and transfer policy. Historical `20260915.01` sources
  open read-only with a notice; the editor does not rewrite them.
- [ ] **S3 — Edit functions.** Red tests then pure functions: add/remove agent or human
  participant, rename a participant (rewriting `handled_by`, `caller`/`callee`, `transfers`,
  route maps and tool visibility overrides), add/remove a transfer, switch direction, set or
  clear a capability override, set a section permission, add/edit/remove variable sections and
  fields, and set first message, tools, wait sounds and media policy.
- [ ] **S4 — Graph projection.** Entry node from the direction block, agent and human nodes,
  transfer edges from `transfers`, deterministic layout (entry, then agents, then human
  destinations, ordered by `transfers`) and no positions in the source.
- [ ] **S5 — Client validation.** Rules returning the same JSON paths the backend uses: required
  fields, string lengths (name 256, description 1,024, transfer notice 4,096, fixed first message
  4,096, prompt 32,768), identifier format, E.164 numbers, ring timeout 5,000 to 60,000, transfer
  attempt timeout 1,000 to 120,000, reference integrity, direction rules (outgoing handler is an
  agent, callee is a human with a phone `dial` connection, no `number_from_variable` on the callee)
  and reserved tool names. A table-driven test checks each rule against the matching V1 backend
  case so client and server paths agree.
- [ ] **S5b — Error placement and messages.** Pure functions mapping a JSON path to a location
  (node or Call settings, tab, field, operator-facing label such as "Agent assistant › Prompt")
  and an error code plus path pattern to toast text, covering every row of the
  [save and publish outcomes](#error-presentation) table. Table-driven tests include unmappable
  paths falling back to the issues list and the backend `reason`.
- [ ] **S6 — New spec seed.** A function returning the default new spec (incoming web caller, one
  agent) with recommended defaults filled from a catalog argument.
- [ ] **Exit S.** Console frontend unit tests, type check and lint pass; no React in this module.

## Checkpoint U — Editor in Storybook

Outcome: the complete editor is reviewable in Storybook with deterministic fixtures, following the
[operator admin Storybook](operator-admin-storybook.md) conventions. Production routes are not
changed.

Each task copies the named Callpipe files from `ui/src/workspace/pages/flow-editor/`, adapts
them as described under [Frontend](#frontend), and copies their existing stories before changing
them, so the first commit of each component shows Callpipe's version and later diffs show the
adaptation.

- [ ] **U1 — Dependencies, theme tokens and primitives.** Add `@xyflow/react` to
  `apps/vxpipe_console/assets/package.json` with its lockfile. In
  `apps/vxpipe_console/assets/src/admin/admin.css`, map the standard shadcn color tokens
  (`background`, `foreground`, `muted`, `muted-foreground`, `border`, `input`, `ring`,
  `primary`, `destructive` and so on) onto the existing `--admin-*` variables in both themes, so
  shadcn components and copied Callpipe markup render in Console colors without per-file
  rewrites. Add a `components.json` for Console assets and install the standard shadcn components
  listed under [Frontend](#frontend) with the shadcn CLI, including the seven Callpipe's editor
  imports (`dialog`, `input`, `item`, `popover`, `skeleton`, `switch`, `tabs`), with their Radix
  dependencies and lockfile. Install unmodified registry versions rather than copying
  Callpipe's local copies. Following the project's Storybook rule, do not add stories for raw
  primitives; one theme check story confirms the token mapping in light and dark themes.
- [ ] **U2 — Shell (copied).** `editor-header` (with `FlowNameDialog`), `editor-toolbar`,
  `flow-canvas`, `flow-node`, `flow-layout` and the canvas half of `flow-editor-layout`. Remove
  the test call and testchat buttons, add revision and published badges and validation state,
  and drive nodes and edges from S's graph projection. Copy the `Header`, `HeaderSaving`,
  `NameDialog`, `Toolbar` and `NodeCards` stories.
- [ ] **U3 — Call settings inspector (adapted from `flow-level-inspector`).** Keep its tab
  structure; drop channels, starters, knowledge and the chat agent. Add tabs Direction, Defaults,
  Variables, Media and recording, Wait sounds, Advanced.
- [ ] **U4 — Entry and human inspectors (adapted from `inbound-inspector` and
  `human-inspector`).** Replace the number pool with the caller or callee connection, turn the
  recording disclosure into opening audio, add the outgoing ring timeout. For humans, keep the
  phone field and add service selection, web destinations, `number_from_variable`, description
  and the private briefing; replace the timing summary with the one transfer attempt timeout.
  Copy the `HumanInspectorDefault` and `InboundInspectorDefault` stories.
- [ ] **U5 — Agent inspector (adapted from `agent-inspector`).** Tabs Prompt, Voice and model,
  Variables, Transfers, Tools, Presence. Model pickers preselect the recommended model and voice, reset them when the provider
  changes, and keep saved choices when opening an existing spec. Tests cover all three.
  Keep Callpipe's tab bar, transfer destination search and the step pattern of `AddToolsModal`
  (source, then tool, then options), rebound to `host`/`mcp`/`platform` tools and conversation
  mode. Replace the prompt editor with a plain textarea, and variable access grants with the
  section permission matrix. Copy and adapt `AgentInspectorDefault`, `AgentVariables` and
  `AgentTransfers`.
- [ ] **U6 — Errors and source view.** Badges on nodes, Call settings and tabs; header issue
  count; issues list; inline messages for the visible tab only; toasts with **Show**,
  **Retry**, **Open services** and **Reload** actions, all per
  [Error presentation](#error-presentation); read-only JSON with copy and download.
- [ ] **U7 — Stories.** Starting from `flow_editor.stories.jsx`, page stories for default,
  loading, load failure, new spec, client validation errors, save blocked by client errors, one
  story per row of the save and publish outcomes table, mappable and unmappable backend errors,
  published revision, outgoing call, historical schema (read-only), narrow viewport and long
  content, with interaction tests for adding a participant, drawing a transfer, renaming,
  following a toast's **Show** action and opening the issues list.
- [ ] **U8 — Review.** Inspect every story with `agent-browser` at desktop and phone widths, then
  stop for the user's review and record the decision here.
- [ ] **Exit U.** Frontend tests and Storybook build pass, rendered inspection is recorded, and
  the user has approved the UI for production integration.

## Checkpoint C — Console authoring endpoints

Outcome: the installation operator can read, save and publish call specs and look up the choices
the editor needs, through Console admin endpoints.

- [ ] **C1 — Red endpoint tests.** In
  `apps/vxpipe_console/test/vxpipe/console/admin_call_specs_endpoint_test.exs`, expect read of
  the latest and a given revision (source, revision, published state, routes), save as new and as
  a new revision, publish, V's error body on invalid sources, `404` for another tenant's spec and
  no credential values in any response.
- [ ] **C2 — Calls read workflow.** Expose reading a revision's source for the installation
  operator through `Vxpipe.Calls`, reusing `fetch_call_spec`.
- [ ] **C3 — Routes.** Add `GET`, `POST`, `PUT` and publish routes under
  `/admin/api/tenants/:tenant_key/call-specs`, calling `CallSpecAuthoring` with
  `InstallationOperator.authority()` and V's shared error projection.
- [ ] **C4 — Lookups.** Credential names per provider from tenant service bindings, telephony
  services from tenant telephony applications, and MCP integration names from the configured
  integration list, all without secret material. MCP tool names stay free text in v1, because
  listing them needs a network call to each server.
- [ ] **Exit C.** Console and Calls suites and root gates pass.

## Checkpoint W — Production editor

Outcome: operators create, edit, save and publish call specs in `/admin`.

- [ ] **W1 — Routes.** Add `/admin/tenants/:tenantKey/call-specs/new` and `/:callSpecId`
  (`?revision=N` read-only) to the React Router table and update
  [Console React routing](../console-react-routing.md).
- [ ] **W2 — API client.** Typed functions for C's endpoints and K's listings, following the
  abort, stale-response and session-expiry handling already used in `adminApi.ts`.
- [ ] **W3 — List integration.** **New call spec** action and row links on `TenantCallSpecsPage`.
- [ ] **W4 — Containers.** Load source and catalog (page error state on failure), save,
  publish, map every response to its toast and placement through S5b and U6, keep unsaved
  changes on every failure, and guard unsaved changes on navigation and reload.
- [ ] **W5 — Rendered check.** With `agent-browser`, create, edit, save, fail validation, publish
  and reopen a spec at desktop and phone widths.
- [ ] **Exit W.** Frontend and Console tests and root gates pass and rendered inspection is
  recorded.

## Checkpoint Z — Final acceptance

- [ ] **Z1** Run every item under [acceptance and failure checks](#acceptance-and-failure-checks)
  and record the evidence.
- [ ] **Z2** Add a Console authoring section to the API guide or a new operator guide.
- [ ] **Z3** Update this milestone, the index entry and the labnote; then run the
  [common implementation gates](index.md#common-implementation-and-verification-gates).

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
  default, and `configure/1` accepts each listed public model with its default voice and rejects an
  unknown model; previously supported Flux concrete IDs remain compatible.
- [ ] With client validation bypassed in a test, the same invalid source is rejected by the
  backend and its errors appear on the matching fields.
- [ ] Open each example under `examples/call-specs/` and save without edits; the saved source
  digest equals the original.
- [ ] A spec saved through the tenant API opens in the editor and every field it uses is visible.
- [ ] Renaming a participant updates all references; the saved spec validates.
- [ ] Every save and publish ends with one toast matching the
  [outcomes table](#error-presentation); **Show** selects the right node and tab and focuses the
  field; an unmappable backend error opens the issues list; unsaved changes survive every
  failure.
- [ ] Editing with client errors raises no toast; saving with client errors sends no request.
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

Reviewed locally 2026-10-08 against Calls authoring, Gateway error projection, the
completed administration prerequisites, direction schema and Console routing/styling
contracts. V → P → L → K establishes shared backend shapes before S → U; C → W
reuses the existing operator authority and immutable revision workflows. No reverse
application dependency is required.

Implementation clarifications: exhausted optimistic revision retries also map to
`409 revision_conflict`; private-material rejection must retain its first field path;
historical stored compiler errors need the same bounded projection as new errors.
The default suite and local synthetic sample acceptance replace any live-provider
execution for this milestone, per the user's explicit instruction. U's concrete
Storybook review remains before production integration. Design review does not
establish implementation completion.
