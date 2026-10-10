# Call spec editor review

Date: 2026-10-08. Task: review the Callpipe flow editor and write a milestone to recreate call spec
authoring in the Vxpipe operator Console. Result:
[call spec editor milestone](milestones/call-spec-editor.md), index entry 42.

## Sources read

- Callpipe: `docs/specs/page-flow-editor.md`, `docs/specs/page-flows.md`,
  `ui/src/workspace/pages/flow-editor/*` (definition, layout, header, inspectors, prompt editor,
  variable retention control), `ui/src/workspace/pages/flows.jsx` and the English workspace
  translation strings for `flowEditor.*`.
- Vxpipe: `Vxpipe.CallEngine.CallSpec` and its `call_spec/*` modules, `docs/call-spec-direction.md`,
  `examples/call-specs/development.json`, Gateway `call_spec_writes.ex`,
  `Vxpipe.Calls.CallSpecAuthoring`, Console router and `AdminCallSpecsController`, Console admin
  React sources and `docs/development/console-react-routing.md`.

## Findings

- Callpipe "flows" are Vxpipe call specs. Callpipe edits a mutable node/edge graph with start,
  agent, human and end nodes, using `@xyflow/react`; the system prompt editor is Lexical in plain
  text mode only.
- Vxpipe's Console lists call specs but cannot create or edit them; authoring is via the tenant API
  or `mix vxpipe.call_spec.*`.
- `CallSpecAuthoring.save/4` and `publish/5` already accept `InstallationOperator` authority, so
  Console endpoints can reuse them without a new authorization path.
- Gateway write responses collapse every validation failure to `invalid_call_spec`; validation
  errors internally carry JSON paths, which the editor needs.
- Remote MCP integrations come from OTP application configuration
  (`RemoteMcp.ApplicationConfiguration`), not tenant storage; the Console has no endpoint listing
  them, nor a provider/model catalog endpoint.
- Callpipe features with no schema equivalent: end nodes/outcomes, knowledge, common prompt,
  per-edge transfer instructions, "any node" destination, transfer acceptance gates, human retry
  and fallback, sensitive variable retention, chat/WhatsApp.
- Vxpipe features Callpipe never exposed: direction and ring timeout, capability defaults and
  overrides, first message modes, transfer history, wait sounds, media policy and `while_present`,
  tool visibility, limits, transfer attempt timeout, `number_from_variable`, JSON Schema variable
  sections with read/write permissions, tool conversation mode.

## Decisions (proposed, pending review)

- Editor state is the portable source; the canvas is a projection, so API-authored specs
  round-trip unchanged. Layout is deterministic and not persisted.
- Storybook first, then production wiring, following the operator admin Storybook precedent.
- User decisions 2026-10-08: no test calls at all; the UI has its own validation, the backend
  validates independently, and the UI shows backend errors on the matching fields. The separate
  "validate without saving" endpoint was dropped; save/publish return field-level errors.
- Callpipe-only features listed for the user to choose which become schema milestones.
- User request 2026-10-08: the tenant API save/publish must return specific errors, so no
  validate endpoint. `CallSpecValidation.invalid/4` already stores `path` and `reason` in
  `Error.details`; Gateway's `call_spec_writes.ex` discards them. The validator is fail-fast
  (`with` chains), so v1 returns one error per response.
- Model listing: Callpipe had no model picker (models hardcoded in its runtime compiler, voices as
  free-text IDs). Vxpipe already depends on `llm_db` 2026.9.1 through ReqLLM, a packaged
  models.dev snapshot. A local probe found google 59, openai 147, deepseek 3, openrouter 559,
  fireworks_ai 19 and zenmux 201 models, including non-chat models (image/video), so the listing
  must filter by output modality and tool support. The runtime resolves models with
  `ReqLLM.model/1` against that snapshot and hand-codes overrides for newer models in
  `ProviderSelection`, so listing from a live models.dev fetch was rejected: it would offer
  models the runtime refuses.
- Audio model lists exist only as private adapter attributes (Cartesia, ElevenLabs, Deepgram Flux,
  fixed Google/GPT-Live models). User decision 2026-10-08: make the model list part of the provider
  contract. The milestone adds a `models/0` callback to the `STTProvider`, `TTSProvider` and
  `STSProvider` behaviours, which the adapters already implement, and has `configure/1` validate
  against it. A registry-driven contract test covers new providers automatically. LLM providers
  have no speech behaviour; their models stay sourced from `llm_db`.
- Defaults: per-provider default models already exist only in the frontend `setupCatalog.json`
  (`defaultModels`), read by the onboarding display and its tests. User decision 2026-10-08:
  pickers preselect each provider's default. The milestone moves defaults into the backend
  declarations and removes them from the JSON.
- User approved the recommended follow-ups 2026-10-08: shared prompt, per-destination transfer
  instructions, transfer acceptance gates, human handoff availability/retry/fallback, and an LLM
  listing with the same descriptor shape. Chat/WhatsApp excluded.

## Checkpoint breakdown (2026-10-08)

The milestone checklist was replaced by nine checkpoints, V → P → L → K → S → U → C → W → Z, in the
format of `simpler-speech-integrations.md`. Placement follows `mix.exs`: Call Engine already
depends on Agent Runtime and Providers, so it hosts the combined model catalog; Calls adds tenant
credential availability; Gateway and Console call Calls. Speech adapters implementing the
behaviours include duplicate Morse sessions under `providers/morse_code/` and
`call_engine/provider/morse_code_*`; both need `models/0`. Publish of an unpublishable draft
currently returns `409` with an `unsupported_call_plan` summary, so checkpoint V covers publish
too. MCP tool names stay free text in v1 because listing them needs a network call to each server.

## Reuse of Callpipe components (2026-10-08)

User direction: copy Callpipe's Storybook-backed editor components and adapt them rather than
rebuilding. Both stacks use Tailwind v4, shadcn-style Radix primitives, class-variance-authority,
cmdk and lucide. Differences to adapt: Callpipe is JSX with `t()` i18n and lucide 0.468; Console is
strict TypeScript, English only, lucide 1.46. The editor imports only seven shadcn primitives
(`dialog`, `input`, `item`, `popover`, `skeleton`, `switch`, `tabs`); Console has none of them
yet beyond a local `Button`. Callpipe's controller, definition and API modules are bound to its
node-data model and are replaced rather than copied.
- Styling: Console already uses Tailwind v4 with shadcn-style components (`admin.css` imports
  `tailwindcss`; `Button.tsx` uses cva and Radix Slot), so "use shadcn" and the plan agree; shadcn
  components are Tailwind-styled source. The real gap is tokens: Callpipe uses standard shadcn
  names (`text-muted-foreground` 89 uses, `border-border` 64, `bg-background` 29) and light-only
  slate colors, while Console defines `--admin-*` variables with a dark default. U1 maps the
  shadcn tokens onto `--admin-*` and the copied markup drops hard-coded slate colors.
- User direction: use standard shadcn components broadly. The milestone now lists the expected
  registry components, installs them with the shadcn CLI (Console has no `components.json` yet)
  instead of copying Callpipe's local copies, and replaces Callpipe's hand-built controls (for
  example the agent inspector's custom tab buttons and native `<select>`) with shadcn ones.

## Error presentation (2026-10-08)

User direction: the editor is too complex to show every error; communicate save outcomes through
toasts. The milestone now defines surfaces (toast, inline for the visible tab only, badges,
header issue count, on-demand issues list, page error state for load failures) and a toast for
every save/publish outcome. Gateway currently maps `revision_conflict` to `503` and
`invalid_telephony_route` and `private_call_spec_material` to generic codes; checkpoint V2b gives
them specific codes so the UI can say what happened.

## Verification

Documentation-only change. Checked milestone links resolve to existing files and the index count
was updated from 41 to 42 specifications.
