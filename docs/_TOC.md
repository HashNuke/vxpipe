# Proposed documentation table of contents

Status: proposal for review, 2026-11-10. This file inventories and proposes the
documentation structure; it does not move documents, establish feature support,
or implement publication to the website.

The starting inventory contains **115 Markdown documents, four JSON reference
files and one Elixir experiment** under `docs/` (about 1.83 MB). The current index
links to only a small part of them. Many documents mix current contracts,
superseded designs, implementation checkpoints and dated verification evidence.

## Recommended structure

Publish **21 pages: one index, 11 usage guides and nine development guides**.
Organize by what a reader needs to do or understand. Keep provider differences
as sections of the relevant guide, and keep one authoritative explanation of
each shared behavior. A new feature normally updates one of these pages.

The proposed paths below are relative to `docs/`; most do not exist yet.
`_TOC.md` is this planning record, not the eventual public index.

```text
docs/
  _TOC.md
  index.md
  usage/
    getting-started.md
    installation.md
    concepts.md
    configuration.md
    administration.md
    integrations.md
    call-specs.md
    telephony.md
    agents-and-tools.md
    api-and-mcp.md
    operations.md
  development/
    local-development.md
    architecture.md
    call-runtime.md
    speech-runtime.md
    agents-and-mcp.md
    security-and-persistence.md
    providers-and-integrations.md
    console-and-clients.md
    testing.md
  assets/                         # Shared diagrams and downloadable examples
```

### Index

`index.md` introduces Vxpipe, explains the two reading paths, and links to every
guide. The usage path starts with a working call; the development path starts
with local setup and architecture. Fold the useful navigation from `README.md`
into this index rather than maintaining two public landing pages.

### Usage: install, configure and operate Vxpipe

These pages explain product behavior and supported workflows. They should be
usable without understanding Elixir process names or internal implementation
checkpoints. The order below is the proposed reading/sidebar order.

| ID | Proposed page | Topics to cover | Work needed |
| --- | --- | --- | --- |
| U1 | **Getting started** — `usage/getting-started.md` | Shortest verified installation path; first account and tenant; connect an AI service; create, publish and run a browser call; observe a tool invocation; next steps toward a phone receptionist. | Rewrite the source quickstart and sample walkthrough into one tested journey. |
| U2 | **Installation and deployment** — `usage/installation.md` | Supported installation methods; prerequisites and PostgreSQL; migrations and startup; persistent data; public HTTPS, proxy and media networking; deployment verification; upgrades. | New operator guide. Source checkout is documented today; verify packaging before offering Docker/release or Railway instructions as runnable recipes. |
| U3 | **Core concepts** — `usage/concepts.md` | Installation, tenant, integration and saved connection; call spec and revision; call, room, participant and agent activation; browser versus phone; LLM + STT/TTS versus native speech-to-speech; variables, history and model context; the two directions of MCP. | New concise explanation drawn from the architecture and domain contracts. |
| U4 | **Configuration** — `usage/configuration.md` | Runtime environment/secrets versus application configuration versus tenant settings; precedence and defaults; Installation URL; database and encryption keyring; provider/model/voice selections; timeouts, limits and catalog refresh intervals. | New consolidated reference grounded in current config and supported settings. Provider credentials belong in saved integrations, not a new collection of deployment variables. |
| U5 | **Tenants, users and access** — `usage/administration.md` | First Superadmin; tenant creation; platform versus tenant scope; users, roles and permissions; sessions, password recovery, API-key issuance/revocation; sample/demo setup where supported. | Merge account operations and access docs; reconcile superseded operator bootstrap instructions. |
| U6 | **Connecting integrations** — `usage/integrations.md` | Native AI/telephony services; listed and custom MCP servers; static authentication and OAuth/CIMD/DCR; save versus credential check; reconnect, replace and disconnect; tool discovery and tenant-specific catalog refresh; unavailable directory/connection recovery. | Extract the implemented Console/API workflow from the many design and Storybook documents. Distinguish the public integration directory from each tenant connection's authorized tool catalog. |
| U7 | **Call specs** — `usage/call-specs.md` | Editor and JSON authoring; incoming/outgoing direction; participants and connections; model/speech selections; variables and nullability; openings, wait sounds and transfer destinations; validation, identity, immutable revisions and publication. | Consolidate the authoring contract and examples. Establish the current schema and ID representation before rewriting. |
| U8 | **Phone calls** — `usage/telephony.md` | Telnyx and Twilio setup; credentials, numbers and service bindings; public callbacks and signature validation; incoming routes; outgoing dialing, answer/no-answer and hangup; transfers; first AI receptionist call and failure diagnosis. | New end-to-end guide using existing telephony contracts. Keep carrier-specific setup in sections; distinguish participant handoff from carrier/PSTN features. |
| U9 | **Agents, speech and tools** — `usage/agents-and-tools.md` | Choosing LLM pipelines or native speech-to-speech; prompts, voices and speech-start settings; openings and interruption; built-in, host, variable and MCP tools; blocking/background behavior; transfers, hangup and context compaction. | New usage guide over the common implementation. Explain tool behavior once for both agent modes, with explicit capability limits. |
| U10 | **HTTP API and platform MCP** — `usage/api-and-mcp.md` | External automation; HTTP API keys versus Console sessions; resource/endpoint reference and examples; tenant/spec/call operations; join tokens and inspection; connect an external AI harness to Vxpipe's OAuth-protected `/mcp`; tool permissions, errors and revocation. | Consolidate API inventory and platform MCP docs. This is the MCP server Vxpipe exposes, distinct from the external MCP connections used inside calls. |
| U11 | **Operations and troubleshooting** — `usage/operations.md` | Health and readiness; call history, transcripts, tool outcomes and diagnostics; logs/metrics; failed or silent calls, failed transfers and reconnects; background jobs and stale MCP catalogs; backup/restore and retention; credential/key rotation; restart and shutdown recovery. | New runbook assembled from operational material. Clearly separate verified procedures from missing delivery, backup or retention work. |

### Development: understand and change Vxpipe

These pages contain current contracts, extension points, ownership and the
rationale needed to maintain them. Keep dated test counts, review transcripts
and step-by-step implementation history in labnotes instead of repeating them
in the handbook.

| ID | Proposed page | Topics to cover | Work needed |
| --- | --- | --- | --- |
| D1 | **Development workflow** — `development/local-development.md` | Prerequisites; `bin/setup`, isolated worktrees/databases/ports and launchers; fixtures; common checks; contribution workflow; repository map; editing and publishing these docs. | Retain the useful local guide and merge worktree guidance. Link operator installation instructions instead of repeating them. |
| D2 | **Architecture** — `development/architecture.md` | Umbrella applications and dependency direction; Console/Gateway/Calls/Persistence boundaries; domain model; ingress-to-call-to-agent-to-output flow; supervision and resource ownership; persistent versus ephemeral state; events and protocol boundaries; embedded use and its delivery status. | Replace the large accumulated architecture narrative with a current system map and links to the deeper chapters. |
| D3 | **Call runtime and lifecycle** — `development/call-runtime.md` | Compilation and prepared plans; admission and readiness; room incarnations and participant ownership; media policy and membership changes; transfers and waits; dial/carrier lifecycle; cancellation, teardown and durable completion. | Merge lifecycle and policy decisions. Preserve failure/ordering invariants without duplicating each old checkpoint. |
| D4 | **Speech and media runtime** — `development/speech-runtime.md` | Semantic STT/TTS/STS contracts; session ownership and persistent transports; input routing, credit/backpressure and output admission; transcript publication and playout settlement; openings, barge-in, stale output, reconnect/resumption and duplex behavior. | Consolidate shared speech invariants. Link adapter-specific examples from D7 instead of explaining the common runtime separately per provider. |
| D5 | **Agent runtime, tools and outbound MCP** — `development/agents-and-mcp.md` | Current model loop and context compaction; common tool descriptors/execution/results for LLM and STS; participant-owned MCP sessions and retirement; transient discovery owners; tenant catalogs, initial refresh and periodic job scheduling; cancellation, limits and external effects. | Merge agent/tool/MCP ownership docs. Cover cached tenant metadata and background jobs separately from live call-owned sessions. |
| D6 | **Identity, persistence and security boundaries** — `development/security-and-persistence.md` | Authorization boundaries and tenant isolation; persistence ports and transactions; encrypted credentials and key rotation; API-key/browser authentication; inbound MCP OAuth versus outbound OAuth grants; discovery/callback/token validation, renewal and fencing; network destinations and sensitive-data handling. | Merge the security-relevant current contracts and storage decisions. Keep user-facing setup in U5/U6/U10. |
| D7 | **Adding providers and integrations** — `development/providers-and-integrations.md` | Provider manifests and capability declarations; credential/model/voice catalogs; adding LLM, speech or carrier adapters; shared semantic requirements and conformance; provider-specific protocol notes; `integrations/` authoring; public catalog publisher/API/cache and JSON references. | Consolidate extension guides and adapter notes. The public directory protocol stays distinct from tenant MCP tool catalogs described in D5. |
| D8 | **Console and client development** — `development/console-and-clients.md` | Phoenix/React routing; API and authorization integration; styling/components; editor source and graph state; call inspection/event reconciliation; WebRTC/RTVI client boundaries; integrations discovery/consent UI; Storybook workflow. | Extract reusable frontend contracts, leaving historical design reviews in labnotes. Link D9 for acceptance procedures. |
| D9 | **Testing and verification** — `development/testing.md` | Focused and umbrella checks; fixtures and deterministic lifecycle tests; browser/Storybook checks; opt-in live provider and telephony lanes; native WebRTC checks; inbound/outbound MCP conformance; Lean models/oracles; bounded load measurements and their limits. | Merge runnable verification guides. Keep exact historical results with the milestone/labnote that owns them. |

## Gaps and conflicts to address during consolidation

- **Installation is not a finished delivery guide.** The repository README labels
  its Docker command a preview, and the website's getting-started page is `TODO`.
  U1/U2 must distinguish verified source execution from unfinished packaging.
- **Product concepts, complete configuration and operator runbooks need writing.**
  They are currently scattered through implementation documents. U3/U4/U11 are
  new guides, not renamed copies of existing pages.
- **Call-spec identity conflicts.** The editor guide describes a public UUID;
  `call-spec-identity.md` describes a database ID encoded as a decimal string.
  Reconcile against the implemented public contract before publishing U7/U10.
- **Older status text is not current feature status.** Several MCP documents
  still describe isolated proposed/Storybook checkpoints while newer ownership
  and shared-tool documents report implemented behavior. Some early speech docs
  say there is no local VAD; the speech-start document describes optional VAD.
  Resolve these in the current guide, rather than publishing both accounts.
- **Do not turn prototypes into promises.** For example, the voice-catalog
  document explicitly describes a proposed backend and working UI prototype.
  Preserve useful future requirements in planning records; advertise only
  implemented and appropriately verified behavior in usage docs.

## Making the result suitable for vxpipe-web

The website already uses Astro/Starlight. Its English documentation destination
is `src/content/docs/en/docs/`; the root `src/content/docs/index.mdx` is the
marketing homepage. The GitHub repository is `HashNuke/vxpipe-web`; its current
local checkout is still `../vxpipe-docs`, relative to the Vxpipe repository root.

The intended flow is **canonical docs in `vxpipe` → copied content in
`vxpipe-web` → website build**, with no separately edited copy of the handbook.
Start with a simple copy/import of the consolidated index and two guide folders.
Decide automation after the topic structure is approved.

Preparation needed for that copy:

1. Give every published page Starlight frontmatter: `title`, `description` and
   `sidebar.order`. None of the 115 existing Markdown docs has frontmatter;
   the installed Starlight schema requires a title. Use a single heading
   convention so the generated page title is not duplicated.
2. Preserve the usage/development folder structure and establish those two
   navigation groups in the website. Keep ordering in page metadata, rather
   than adding numbers to filenames.
3. Normalize documentation links to the routes the site builds. Source-relative
   `.md` links and links escaping into `apps/`, `bin/` or `labnotes/` cannot be
   assumed to work after a raw copy. Use repository links for code/history and
   verify internal links and fragments in the built site. Choose the exact
   link-conversion rule with the import plan.
4. Keep images, diagrams and JSON examples with the docs. Explicitly publish
   downloadable files as static assets; copying JSON beside content Markdown
   does not itself give those files a public download route. Keep diagrams
   readable with the site's actual renderer; no site-only component dependency
   is needed for ordinary guide content.
5. Publish the curated handbook, not the planning inventory or experiments.
   `_TOC.md` stays a review artifact; the installed Starlight loader already
   excludes filenames beginning with `_`. Move useful dated evidence to
   existing labnotes/milestones, and keep the Boruta probe outside the handbook.
6. Replace superseded standalone pages as their content is consolidated. Do not
   retain a second legacy handbook or add compatibility pages merely to preserve
   the old file layout. Update repository links and verify the copied site build.

This proposal adds no importer, CI workflow, page stubs or website changes.
The next step is agreeing on these topics and their scope before moving content.

## Complete source inventory

Each pre-existing file is mapped below to its main destination. Some need to be
split: put user instructions in the usage guide and implementation rationale in
the corresponding development guide, with links between them. Preserve current
contracts; retain historical evidence only where it is useful in labnotes.
The destination IDs refer to the tables above, not implementation milestones.

| Existing file | Main destination | Consolidation note |
| --- | --- | --- |
| [README.md](README.md) | Index | Replace its public navigation role with the proposed index.md. |
| [api-key-access.md](api-key-access.md) | U5 |  |
| [architecture.md](architecture.md) | D2 | Extract the current system map; distribute detailed contracts to D3–D7 and move historical checkpoints out. |
| [call-hangup-lifecycle.md](call-hangup-lifecycle.md) | D3 |  |
| [call-inspection-json-endpoint.md](call-inspection-json-endpoint.md) | U11 | User inspection workflow in U11; internal projection/reconciliation in D8; public API in U10. |
| [call-spec-direction.md](call-spec-direction.md) | U7 |  |
| [call-spec-editor-guide.md](call-spec-editor-guide.md) | U7 | Reconcile ID and schema statements with the current contract. |
| [call-spec-editor-source.md](call-spec-editor-source.md) | D8 |  |
| [call-spec-identity.md](call-spec-identity.md) | U7 | Use to resolve the conflicting identity descriptions in other guides. |
| [carrier-hangup-lifecycle.md](carrier-hangup-lifecycle.md) | D3 |  |
| [console-authentication-and-authorization.md](console-authentication-and-authorization.md) | U5 | Split operator permissions/how-to (U5) from enforcement/storage contracts (D6). |
| [console-authentication-route-inventory.md](console-authentication-route-inventory.md) | D6 |  |
| [console-call-directory.md](console-call-directory.md) | U11 |  |
| [console-credential-management.md](console-credential-management.md) | U6 |  |
| [console-sample-call-catalog.md](console-sample-call-catalog.md) | U1 |  |
| [console-sidebar-navigation.md](console-sidebar-navigation.md) | D8 |  |
| [context-compaction.md](context-compaction.md) | D5 |  |
| [debug-console-call-details-model.md](debug-console-call-details-model.md) | D8 |  |
| [deepgram-voice-selection.md](deepgram-voice-selection.md) | D7 |  |
| [demo-tenant-binding.md](demo-tenant-binding.md) | U5 |  |
| [development/authentication-storybook.md](development/authentication-storybook.md) | D9 | Keep instructions for maintained stories; move review history/obsolete mock workflows to labnotes. |
| [development/console-authentication-operations.md](development/console-authentication-operations.md) | U5 |  |
| [development/console-react-routing.md](development/console-react-routing.md) | D8 |  |
| [development/formal-verification.md](development/formal-verification.md) | D9 |  |
| [development/installation-url-storybook.md](development/installation-url-storybook.md) | D9 | Keep instructions for maintained stories; move review history/obsolete mock workflows to labnotes. |
| [development/integrations-catalog-source.md](development/integrations-catalog-source.md) | D7 |  |
| [development/integrations-directory-api.md](development/integrations-directory-api.md) | D7 | Keep the public directory contract and its referenced JSON assets together. |
| [development/integrations-directory-consumption.md](development/integrations-directory-consumption.md) | D7 |  |
| [development/integrations-directory.categories.example.json](development/integrations-directory.categories.example.json) | D7 | Reference asset for D7; publish a download explicitly if the guide links to it. |
| [development/integrations-directory.example.json](development/integrations-directory.example.json) | D7 | Reference asset for D7; publish a download explicitly if the guide links to it. |
| [development/integrations-directory.schema.json](development/integrations-directory.schema.json) | D7 | Reference asset for D7; publish a download explicitly if the guide links to it. |
| [development/integrations-directory.search.example.json](development/integrations-directory.search.example.json) | D7 | Reference asset for D7; publish a download explicitly if the guide links to it. |
| [development/integrations-ui.md](development/integrations-ui.md) | U6 |  |
| [development/listed-mcp-connections.md](development/listed-mcp-connections.md) | U6 |  |
| [development/live-provider-tests.md](development/live-provider-tests.md) | D9 |  |
| [development/live-telephony-harness.md](development/live-telephony-harness.md) | D9 |  |
| [development/local-development.md](development/local-development.md) | D1 |  |
| [development/mcp-browser-acceptance.md](development/mcp-browser-acceptance.md) | D9 |  |
| [development/mcp-client-conformance.md](development/mcp-client-conformance.md) | D9 |  |
| [development/mcp-connection-checks.md](development/mcp-connection-checks.md) | D5 |  |
| [development/mcp-discovery.md](development/mcp-discovery.md) | D5 |  |
| [development/mcp-oauth-browser-flow.md](development/mcp-oauth-browser-flow.md) | D6 |  |
| [development/mcp-oauth-protocol.md](development/mcp-oauth-protocol.md) | D6 |  |
| [development/mcp-oauth-renewal.md](development/mcp-oauth-renewal.md) | D6 |  |
| [development/mcp-oauth-storage.md](development/mcp-oauth-storage.md) | D6 |  |
| [development/mcp-oauth-ui.md](development/mcp-oauth-ui.md) | D8 |  |
| [development/mcp-runtime-transport.md](development/mcp-runtime-transport.md) | D6 | Credential/transport security in D6; session lifetime cross-reference in D5. |
| [development/mcp-services-storybook.md](development/mcp-services-storybook.md) | D9 | Keep instructions for maintained stories; move review history/obsolete mock workflows to labnotes. |
| [development/native-sts-tools.md](development/native-sts-tools.md) | D5 | Shared behavior for LLM and STS; extract user-facing behavior into U9. |
| [development/native-webrtc-testing.md](development/native-webrtc-testing.md) | D9 |  |
| [development/participant-mcp-ownership.md](development/participant-mcp-ownership.md) | D5 | Current session and catalog-job ownership; baseline findings and dated proof move out. |
| [development/platform-mcp-acceptance.md](development/platform-mcp-acceptance.md) | D9 |  |
| [development/react-component-styling.md](development/react-component-styling.md) | D8 |  |
| [development/saved-mcp-runtime.md](development/saved-mcp-runtime.md) | D5 |  |
| [development/sidebar-navigation-storybook.md](development/sidebar-navigation-storybook.md) | D9 | Keep instructions for maintained stories; move review history/obsolete mock workflows to labnotes. |
| [development/sts-comparative-call-load.md](development/sts-comparative-call-load.md) | D9 |  |
| [development/tenant-mcp-management.md](development/tenant-mcp-management.md) | U6 |  |
| [development/tenant-mcp-oauth.md](development/tenant-mcp-oauth.md) | D6 |  |
| [development/tenant-mcp-storage.md](development/tenant-mcp-storage.md) | D6 |  |
| [development/worktree-isolation.md](development/worktree-isolation.md) | D1 |  |
| [elevenlabs-realtime-models.md](elevenlabs-realtime-models.md) | D7 |  |
| [elevenlabs-stt-session.md](elevenlabs-stt-session.md) | D7 |  |
| [experiments/boruta-probe.exs](experiments/boruta-probe.exs) | Labnotes / experiment | Move outside published docs if still useful; never run as part of a documentation build. |
| [gateway-console-boundary.md](gateway-console-boundary.md) | D2 |  |
| [gemini-live-session-lifecycle.md](gemini-live-session-lifecycle.md) | D7 |  |
| [getting-started-elixir.md](getting-started-elixir.md) | U1 | Separate first-use guide (U1), contributor setup (D1), and embedding status (D2). |
| [google-speech-integration.md](google-speech-integration.md) | D7 |  |
| [google-sts-controller.md](google-sts-controller.md) | D7 |  |
| [gpt-live-reseed-tool-results.md](gpt-live-reseed-tool-results.md) | D7 |  |
| [gpt-live-room-history.md](gpt-live-room-history.md) | D7 |  |
| [incremental-media-policy.md](incremental-media-policy.md) | D3 |  |
| [inline-provider-selections.md](inline-provider-selections.md) | U4 |  |
| [installation-url.md](installation-url.md) | U4 |  |
| [llm-model-catalog.md](llm-model-catalog.md) | D7 |  |
| [mcp-oauth.md](mcp-oauth.md) | D6 |  |
| [native-sts-opening.md](native-sts-opening.md) | D4 |  |
| [opening-audio-contract.md](opening-audio-contract.md) | U7 |  |
| [operator-api-key-authoring.md](operator-api-key-authoring.md) | U5 |  |
| [outgoing-call-runtime.md](outgoing-call-runtime.md) | D3 |  |
| [output-recognition-settlement.md](output-recognition-settlement.md) | D4 |  |
| [persistent-speech-sessions.md](persistent-speech-sessions.md) | D4 |  |
| [phone-connection-picker.md](phone-connection-picker.md) | U8 |  |
| [platform-credential-reencryption.md](platform-credential-reencryption.md) | U11 |  |
| [platform-mcp.md](platform-mcp.md) | U10 | External client setup/tool reference in U10; server architecture and enforcement in D2/D6. |
| [private-policy-continuity.md](private-policy-continuity.md) | D3 |  |
| [product-api-inventory.md](product-api-inventory.md) | U10 |  |
| [product-http-api.md](product-http-api.md) | U10 |  |
| [protected-agent-openings.md](protected-agent-openings.md) | D4 |  |
| [provider-credential-storage.md](provider-credential-storage.md) | D6 |  |
| [provider-credential-validation.md](provider-credential-validation.md) | U6 | Clearly distinguish credential testing, saving, and readiness for a real call. |
| [provider-integration-packages.md](provider-integration-packages.md) | D7 |  |
| [provider-voice-catalog.md](provider-voice-catalog.md) | D7 | Separate proposed backend requirements from implemented capabilities before publication. |
| [readiness-change-notification.md](readiness-change-notification.md) | D3 |  |
| [readiness-resource-contract.md](readiness-resource-contract.md) | D3 |  |
| [remote-morse-code-audio.md](remote-morse-code-audio.md) | D7 |  |
| [reqllm-agent-runtime.md](reqllm-agent-runtime.md) | D5 |  |
| [room-policy-failure-ownership.md](room-policy-failure-ownership.md) | D3 |  |
| [scoped-telnyx-service-bindings.md](scoped-telnyx-service-bindings.md) | U8 |  |
| [speech-integration-guide.md](speech-integration-guide.md) | D7 | Retain the extension recipe; refer to D4 for normative semantics. |
| [speech-model-catalog.md](speech-model-catalog.md) | D7 |  |
| [speech-provider-contract.md](speech-provider-contract.md) | D4 | Current shared semantics in D4; implementation recipe links to D7. |
| [speech-session-ownership.md](speech-session-ownership.md) | D4 |  |
| [speech-transport-privacy.md](speech-transport-privacy.md) | D6 |  |
| [spoken-barge-in.md](spoken-barge-in.md) | D4 |  |
| [stale-speech-output.md](stale-speech-output.md) | D4 |  |
| [sts-agent-output-retirement.md](sts-agent-output-retirement.md) | D4 |  |
| [sts-caller-publication.md](sts-caller-publication.md) | D4 |  |
| [sts-context-restoration.md](sts-context-restoration.md) | D4 |  |
| [sts-duplex-profile.md](sts-duplex-profile.md) | D7 | Keep relevant adapter differences; historical provider research belongs in labnotes. |
| [sts-input-routing.md](sts-input-routing.md) | D4 |  |
| [sts-output-admission.md](sts-output-admission.md) | D4 |  |
| [stt-speech-start-detection.md](stt-speech-start-detection.md) | U9 |  |
| [tenant-control-plane.md](tenant-control-plane.md) | D6 |  |
| [tenant-mcp-integrations.md](tenant-mcp-integrations.md) | U6 |  |
| [tenant-telephony-services.md](tenant-telephony-services.md) | U8 |  |
| [tool-execution-model.md](tool-execution-model.md) | D5 |  |
| [transfer-admission-lifecycle.md](transfer-admission-lifecycle.md) | D3 |  |
| [typed-turn-interruption.md](typed-turn-interruption.md) | D4 |  |
| [variable-nullability.md](variable-nullability.md) | U7 |  |
| [wait-sound-streaming.md](wait-sound-streaming.md) | D4 |  |
