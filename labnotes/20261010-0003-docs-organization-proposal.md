# Documentation organization proposal

Date: 2026-10-10 UTC
Status: development organization approved and implemented; ten docs moved without content refinement. The remaining 59 docs and README are still proposed work.

## Recommendation

Use `docs/README.md` as the documentation landing page and table of contents. The user clarified that name after initially suggesting `docs/index.md`. Put topic pages in `guides/`, `reference/` and `development/`, with vendor-specific references in `reference/providers/`. Avoid additional directory depth initially.

The updated map has 42 topic pages plus the README: eight task guides, 24 contract/reference pages and ten contributor/testing pages. These are editorial boundaries, not a quota; a final content audit can justify another focused page if a subject cannot be covered clearly. Every one of the 69 current source files has an explicit destination below. Two sources intentionally split across two primary pages, and large mixed documents contribute sections to additional named references.

Organize by reader task and contract ownership. A guide explains how to do something; a reference owns the exact supported fields, events, bounds or lifecycle; a development page explains how to change or verify the project. Link between these views rather than duplicate normative definitions. Provider-specific behavior has its own pages while shared speech behavior has one canonical home.

## Proposed tree

```text
docs/
  README.md
  guides/
    quickstart.md
    tenants-and-api-keys.md
    provider-credentials.md
    call-spec-editor.md
    example-calls.md
    inspect-calls.md
    writing-speech-providers.md
    writing-sts-providers.md
  reference/
    architecture.md
    call-specs.md
    operator-api.md
    credentials.md
    telephony-services.md
    telephony-calls.md
    call-inspection.md
    browser-client.md
    agent-runtime.md
    tool-execution.md
    context-management.md
    openings.md
    media-policy.md
    readiness.md
    turns-and-interruption.md
    speech-sessions.md
    speech-provider-api.md
    sts-provider-api.md
    sts-room-lifecycle.md
    provider-registry.md
    providers/
      deepgram.md
      google.md
      openai-live.md
      elevenlabs.md
  development/
    local-development.md
    worktree-isolation.md
    live-provider-tests.md
    live-telephony-harness.md
    native-webrtc-testing.md
    sts-comparative-call-load.md
    formal-verification.md
    mcp-client-conformance.md
    console-react-routing.md
    react-component-styling.md
```

## README navigation

The README should be a short navigation page with these reader-oriented headings:

1. **Start here**: quickstart, example calls and architecture overview. State the currently supported installation path and link Docker packaging availability to its existing milestone.
2. **Operate Vxpipe**: tenants/keys, provider credentials, author/edit/publish, inspect calls; link operator API and telephony references beside the relevant tasks.
3. **Integrate and extend**: embedding/application boundaries, browser client, call specs, provider registry, the two provider-writing guides and vendor pages.
4. **Runtime contracts**: agent/tools/context, openings/interruption, policy/readiness, speech sessions, shared speech APIs and STS room lifecycle.
5. **Develop and verify**: checkout setup, Console UI, live providers, carrier/media/load lanes, Lean and MCP.

Link directly to documents or their stable headings. The README owns navigation, not an implementation checklist, exhaustive configuration copy, or status journal. Each topic page should have a short purpose, relevant prerequisites and a small local table of contents when useful.

## File-by-file merge and split plan

Current file links below point to the current source documents, including the ten development docs now moved. Guide/reference destination paths and content refinements are proposed; only development paths are implemented. Multiple source files in one row merge into sections of one document. A source occurring twice is an intentional split, not duplicated content.

Historical decisions/test-run tables in these remaining sources should be preserved in relevant labnotes as part of eventual refinement, with links from durable contracts. Pending implementation scope stays in the owning milestone. The prior 35 archives and 12 milestone companions remain unchanged.

### Task guides — 8 pages

| Proposed document | Current sources | Main headings | Merge/split decision |
| --- | --- | --- | --- |
| `docs/guides/quickstart.md` | [getting-started-elixir.md](../docs/getting-started-elixir.md) | Prerequisites; initialize with bin/setup; configure a first sample; make a call; next steps | Refine the source walkthrough. Link contributor setup and embedding architecture for advanced details; expose Docker availability via its milestone rather than a speculative install guide. |
| `docs/guides/tenants-and-api-keys.md` | [tenant-control-plane.md](../docs/tenant-control-plane.md), [demo-tenant-binding.md](../docs/demo-tenant-binding.md) | Create/resume a tenant; demo binding; tenant key scopes; reveal/rotate/revoke keys; save/publish overview | Merge operator workflows and demo identity behavior. Send installation operator keys to operator-api, provider setup to its guide, database setup to development/setup. |
| `docs/guides/provider-credentials.md` | [console-credential-management.md](../docs/console-credential-management.md), [provider-credential-storage.md](../docs/provider-credential-storage.md), [platform-credential-reencryption.md](../docs/platform-credential-reencryption.md) | Connect/test/save a provider; tenant and platform scope; replace/remove a binding; rotate platform encryption keys; troubleshoot | Merge UI and CLI tasks, keeping encryption-key rotation as a separate clearly labeled section. Split storage/resolution/API invariants into reference/credentials; upstream key rotation is a different operation. |
| `docs/guides/call-spec-editor.md` | [call-spec-editor-guide.md](../docs/call-spec-editor-guide.md), [call-spec-editor-source.md](../docs/call-spec-editor-source.md) | Create/edit; source JSON; validation; save and publish; conflicts/recovery; read-only revisions | Merge the practical editing/source workflow. Keep lossless/exact-integer rules visible; extract HTTP/error contracts into operator-api and client implementation details into development/console-ui. |
| `docs/guides/example-calls.md` | [console-sample-call-catalog.md](../docs/console-sample-call-catalog.md) | Choose an example; prerequisites; install without overwrite; run; handoff seats | Keep separate: an example catalog is a task guide, not a general schema or a developer fixture inventory. |
| `docs/guides/inspect-calls.md` | [console-call-directory.md](../docs/console-call-directory.md) | Find/filter a call; live versus ended views; outcomes/timestamps; completeness and gaps | Refine into operator navigation/troubleshooting. Link inspection reference for response shape; do not imply pending live console features are delivered. |
| `docs/guides/writing-speech-providers.md` | [speech-integration-guide.md](../docs/speech-integration-guide.md) | Choose STT/TTS; descriptors; minimal provider; input/output; cancellation; register and test | Split the authoring guide: retain common/STT/TTS instructions and runnable minimal TTS example here. Normative callback/event details live in speech-provider-api. |
| `docs/guides/writing-sts-providers.md` | [speech-integration-guide.md](../docs/speech-integration-guide.md) | Choose STS turn control; minimal session; input/output admission; transcripts; tools/history; register and test | Move the advanced STS walkthrough/examples into a separate author guide, linking shared speech rules and STS-specific API/reference. Do not duplicate normative definitions. |

### References — 24 pages

| Proposed document | Current sources | Main headings | Merge/split decision |
| --- | --- | --- | --- |
| `docs/reference/architecture.md` | [architecture.md](../docs/architecture.md), [gateway-console-boundary.md](../docs/gateway-console-boundary.md) | Domain terms; applications/dependencies; supervision; gateway and Console; embedding/composition; persistence boundaries | Major split: this is the overview and embedding boundary, not the 4,145-line implementation notebook. Redistribute detailed contracts to the references below; archive historical checkpoints and keep planned work in milestones. |
| `docs/reference/call-specs.md` | [call-spec-direction.md](../docs/call-spec-direction.md), [inline-provider-selections.md](../docs/inline-provider-selections.md) | Schema/versioning; incoming/outgoing; participants/providers/options; credentials names; openings/tools/media links; immutable plans | Merge direction and inline-selection authoring contracts. Import canonical schema/configuration material from architecture, with links to specialist contracts rather than copying them. |
| `docs/reference/operator-api.md` | [operator-api-key-authoring.md](../docs/operator-api-key-authoring.md) | Installation authority; operator key lifecycle; call-spec requests/revisions; validation/errors; outgoing submission; catalog endpoints | Split the current mixed key/authoring/outgoing/catalog document into a maintained HTTP/CLI authority/API reference, linking catalog semantics, call spec schema and telephony lifecycle. Keep route ownership explicit: Console operator endpoints versus Gateway call admission. |
| `docs/reference/credentials.md` | [provider-credential-validation.md](../docs/provider-credential-validation.md) | Test versus Save; payload/status contracts; encrypted storage; precedence and authoring authority; pinned identity and reader lifetime; privacy | Combine API semantics with the storage/resolution invariants extracted from provider-credential-storage. Link the operator guide for procedures and accepted scoped-services companion for provenance. |
| `docs/reference/telephony-services.md` | [tenant-telephony-services.md](../docs/tenant-telephony-services.md), [scoped-telnyx-service-bindings.md](../docs/scoped-telnyx-service-bindings.md) | Service/binding identity; platform/tenant scope; application/number configuration; webhook verification/dispatch; media authentication; origins | Merge service configuration, scoped authentication and retained identity. Keep these configuration/security contracts separate from call-state and dial lifecycle. |
| `docs/reference/telephony-calls.md` | [outgoing-call-runtime.md](../docs/outgoing-call-runtime.md), [carrier-hangup-lifecycle.md](../docs/carrier-hangup-lifecycle.md), [transfer-admission-lifecycle.md](../docs/transfer-admission-lifecycle.md) | Incoming/outgoing admission; idempotency; dial/ring/AMD; handoff admission; physical answer; hangup/failure/unknown outcome | Merge call-lifetime contracts. Extract common prepared/join/transfer admission from architecture here with clear per-flow scope; protocol envelopes remain in browser-client. |
| `docs/reference/call-inspection.md` | [call-inspection-json-endpoint.md](../docs/call-inspection-json-endpoint.md) | Inspection routes; persisted baseline; schema/completeness; artifacts; errors/privacy | Keep backend inspection API separate from operator UI and client reconciliation. Pull durable archive/publication/security invariants from architecture where they actually apply. |
| `docs/reference/browser-client.md` | [debug-console-call-details-model.md](../docs/debug-console-call-details-model.md) | Core/React boundary; host adapters; call detail model; revisions/tombstones; loading/reconnect; supported RTVI envelopes | Refine the client model reference and import supported protocol projection from architecture/interruption docs. Typed interfaces alone do not prove a live adapter or private-variable extension exists. |
| `docs/reference/agent-runtime.md` | [reqllm-agent-runtime.md](../docs/reqllm-agent-runtime.md) | Package boundary; request/session ownership; submit/commit; queue/history; failure/termination | Keep distinct from tools and context accounting: runtime lifecycle has its own API and responsibility. Extract matching architecture detail; archive dependency-selection/probe chronology. |
| `docs/reference/tool-execution.md` | [tool-execution-model.md](../docs/tool-execution-model.md) | Bindings/policy; blocking/nonblocking work; worker ownership; private results; deadlines/cancellation; failure outcomes | Keep tools separate. Scope text-agent continuations explicitly; STS tool/provider-specific result admission is linked to its own contracts, with unresolved design kept in milestones. |
| `docs/reference/context-management.md` | [context-compaction.md](../docs/context-compaction.md) | Budget/accounting; protected history; summaries; recipient authority; supported provider fallback; failure preservation | Keep one focused context/compaction reference. Session reconnect/reseed is a different contract and lives in STS lifecycle/provider pages. |
| `docs/reference/openings.md` | [opening-audio-contract.md](../docs/opening-audio-contract.md), [native-sts-opening.md](../docs/native-sts-opening.md), [protected-agent-openings.md](../docs/protected-agent-openings.md) | Fixed/file/generated openings; limits/assets; once-only admission; protected playback; text buffering versus STS discard; provider exceptions | Merge the three opening docs. Separate authoring examples from runtime semantics with headings, and link speech sessions/STS for shared lifecycle rules. |
| `docs/reference/media-policy.md` | [incremental-media-policy.md](../docs/incremental-media-policy.md), [private-policy-continuity.md](../docs/private-policy-continuity.md), [room-policy-failure-ownership.md](../docs/room-policy-failure-ownership.md) | Policy intervals; preserving/replacing resources; private preparation; critical registration; commit/promotion; failure ownership | Merge the policy contract and remove per-checkpoint repetition. Readiness imports policy identity but does not restate policy enforcement. |
| `docs/reference/readiness.md` | [readiness-resource-contract.md](../docs/readiness-resource-contract.md), [readiness-change-notification.md](../docs/readiness-change-notification.md), [wait-sound-streaming.md](../docs/wait-sound-streaming.md) | Required resource identity; evidence/generations; prospective inventory; barrier/deadlines; Watch notifications; preparation/adoption; wait sounds | Major refinement: collapse the 1,197-line evolving journal into one supported contract. Keep the resource/adaptor inventory as tables and sequence headings; archive phase evidence and keep incomplete integration gates in the owning milestone. |
| `docs/reference/turns-and-interruption.md` | [typed-turn-interruption.md](../docs/typed-turn-interruption.md), [spoken-barge-in.md](../docs/spoken-barge-in.md), [stale-speech-output.md](../docs/stale-speech-output.md) | Text versus speech turns; typed interruption; acoustic onset/barge-in; sink-first cancellation; stale output; audible history; echo/protected-opening limits | Merge all interruption types while distinguishing their triggers and ownership. Move protocol payloads to browser-client and link provider-specific STS interruption rather than inventing universal behavior. |
| `docs/reference/speech-sessions.md` | [speech-session-ownership.md](../docs/speech-session-ownership.md) | Owner versus lease/consumer; scoped supervision; prepare/adopt; identities; deadlines; capability/allocation failures | Keep runtime ownership separate from the provider callback API. Absorb matching architecture lifecycle sections and link media policy/readiness instead of repeating them. |
| `docs/reference/speech-provider-api.md` | [speech-provider-contract.md](../docs/speech-provider-contract.md), [speech-transport-privacy.md](../docs/speech-transport-privacy.md), [output-recognition-settlement.md](../docs/output-recognition-settlement.md) | STT/TTS descriptors/callbacks; event schemas; PCM/credit; requests/cancellation; finite input and settlement; bounds/privacy/errors | Split semantic contract into the common/STT/TTS reference and STS extension. Merge transport privacy and finite-input semantics here, preserving qualified hosted support. Move research/migration narratives into evidence notes. |
| `docs/reference/sts-provider-api.md` | [speech-provider-contract.md](../docs/speech-provider-contract.md), [sts-output-admission.md](../docs/sts-output-admission.md) | STS descriptor facts; input context; output admission/credit; transcripts/settlement; interruption/close; provider tool boundary | Extract STS-only callbacks/events from the semantic contract and merge the output-admission contract. Common types and lifetime rules link to speech-provider-api/speech-sessions; the room controller is a separate page. |
| `docs/reference/sts-room-lifecycle.md` | [sts-input-routing.md](../docs/sts-input-routing.md), [sts-caller-publication.md](../docs/sts-caller-publication.md), [sts-agent-output-retirement.md](../docs/sts-agent-output-retirement.md), [gpt-live-room-history.md](../docs/gpt-live-room-history.md), [sts-context-restoration.md](../docs/sts-context-restoration.md) | Source selection/epochs; routing/formats; public caller/output identity; transcript retirement; history snapshots; reconnect/handoff; capability limits | Merge room-owned STS rules and common history privacy. Split Google handle-specific restoration into providers/google and GPT-Live reseed specifics into providers/openai-live. Proposed fresh-session reconstruction stays in the milestone. |
| `docs/reference/provider-registry.md` | [provider-integration-packages.md](../docs/provider-integration-packages.md), [llm-model-catalog.md](../docs/llm-model-catalog.md), [speech-model-catalog.md](../docs/speech-model-catalog.md) | Installed manifests; supported/configured/ready; LLM/speech model-list schemas; voice/default/recommendation rules; filtering/discovery; registering a provider | Merge the registry and catalogs into one canonical reference. Use separate LLM and speech headings/tables; individual provider options live in provider pages. Generate capability inventories from source instead of copying stale snapshots. |
| `docs/reference/providers/deepgram.md` | [deepgram-voice-selection.md](../docs/deepgram-voice-selection.md) | Supported STT/TTS selections; voices/model aliases; options/formats; limits; setup links | Keep a vendor-specific selection page. Link shared session/API references and archived native/finite-input findings for provenance; optionally restore necessary wire details from archives during refinement. |
| `docs/reference/providers/google.md` | [google-speech-integration.md](../docs/google-speech-integration.md), [google-sts-controller.md](../docs/google-sts-controller.md), [gemini-live-session-lifecycle.md](../docs/gemini-live-session-lifecycle.md) | STT/TTS/STS capability table; model/voice/options; caller/output control; interruptions; session renewal/resumption; limits | Merge Google configuration and controller/lifetime rules; import provider-specific restoration from sts-context-restoration. Keep chronological probes out of the main guide and distinguish qualified hosted evidence from general support. |
| `docs/reference/providers/openai-live.md` | [sts-duplex-profile.md](../docs/sts-duplex-profile.md), [gpt-live-reseed-tool-results.md](../docs/gpt-live-reseed-tool-results.md) | Auth/setup; formats; duplex behavior; tools; transcript/usage limits; close/errors; reconnect/reseed/results | Merge the profile and lost-session tool-result rules; add provider-specific reseed details from gpt-live-room-history. Reconcile the later repeated-reseed repair against current source before publishing limits. |
| `docs/reference/providers/elevenlabs.md` | [elevenlabs-stt-session.md](../docs/elevenlabs-stt-session.md) | Supported STT scope; model/options; local_gap/manual turn semantics; startup/admission; limits; setup | Keep provider-specific acoustic-versus-recognition behavior here, linking common speech APIs. Do not import deferred hosted-agent STS as supported scope. |

### Development and verification — 10 separate pages

**2026-10-10 approved organization:** the user selected development documentation as
the first implementation checkpoint and asked to keep unrelated topics separate.
The original setup and Console UI merges are superseded: local development and
checkout isolation remain separate, as do Console routing and React styling.
All ten source documents now live under `docs/development/`; `development.md` is
named `local-development.md`, and the other nine retain their basenames. The
[checkpoint labnote](20261010-0014-organize-development-docs.md) records the actual
path map and checks. This checkpoint preserves content; the proposed substantive
refinements, archival extraction and `docs/README.md` remain future work. The updated tree and rows below reflect 42 topic pages plus README, rather
than the original 40 plus README.

| Proposed document | Current sources | Main headings | Merge/split decision |
| --- | --- | --- | --- |
| `docs/development/local-development.md` | [local-development.md](../docs/development/local-development.md) | Tools; bin/setup; bin/dev; fixtures; PostgreSQL; HTTPS/reload; release assets | Moved independently. Future refinement can clarify local development without combining checkout isolation. |
| `docs/development/worktree-isolation.md` | [worktree-isolation.md](../docs/development/worktree-isolation.md) | Identity; database/output/secrets isolation; ports; recovery; acceptance limits | Moved independently. Keep the ownership/default-selection and recovery contract separate, cross-linked from local development. |
| `docs/development/live-provider-tests.md` | [live-provider-tests.md](../docs/development/live-provider-tests.md) | Prerequisites/credential handling; lane selection; fixtures/cost bounds; evidence levels; cleanup/troubleshooting | Keep the generic live-test runner/lane guide; link separate telephony and provider pages, and archive dated acceptance tables. |
| `docs/development/live-telephony-harness.md` | [live-telephony-harness.md](../docs/development/live-telephony-harness.md) | Branch ownership; release; public ingress; carrier resource provisioning; two-call scenarios; bounded cleanup; troubleshooting | Keep separate from the generic provider guide because carrier resources, Funnel and cleanup ownership have distinct operational requirements. Archive hundreds of lines of dated carrier runs. |
| `docs/development/native-webrtc-testing.md` | [native-webrtc-testing.md](../docs/development/native-webrtc-testing.md) | Local network lane; codecs; startup/transfer scenarios; audio evidence; decoder/fixture checks; limits | Keep native WebRTC/media verification separate from carrier credentials and hosted tests; archive individual diagnostic investigations. |
| `docs/development/sts-comparative-call-load.md` | [sts-comparative-call-load.md](../docs/development/sts-comparative-call-load.md) | Smoke/measured commands; workloads/modes; metrics/bounds; environment controls; evidence limits | Keep reproducible harness instructions; archive old timing result tables next to their artifacts. This is not a production capacity promise. |
| `docs/development/formal-verification.md` | [formal-verification.md](../docs/development/formal-verification.md) | Toolchain; run bin/verify-lean; models/oracles/replay; add a model; proof limits | Keep a dedicated maintained tool guide; verify actual model inventory and move the original proposed slice order into historical records. |
| `docs/development/mcp-client-conformance.md` | [mcp-client-conformance.md](../docs/development/mcp-client-conformance.md) | Pinned profile/fork; conformance runners; Everything fixture; privacy/errors; reproduction; exact limits | Keep the lane and maintained-fork contract separate from speech testing. Move old upstream/branch/run ledgers to existing MCP history. |
| `docs/development/console-react-routing.md` | [console-react-routing.md](../docs/development/console-react-routing.md) | Phoenix document routes; data-router ownership; package boundary; navigation/editor state | Moved independently. Keep contributor routing guidance separate from styling and client-consumer APIs. |
| `docs/development/react-component-styling.md` | [react-component-styling.md](../docs/development/react-component-styling.md) | Tailwind utilities; semantic tokens; package CSS/imports; source distribution | Moved independently. Keep styling and distribution guidance separate from Console routing; do not claim unpublished registry distribution. |

## Important section splits

### Architecture

The current `architecture.md` is 4,145 lines. Keep terms, application/dependency boundaries, runtime overview, engine/protocol separation and embedding/composition in the architecture page. Move exact call-spec/configuration contracts to `call-specs.md`; client/RTVI envelopes to `browser-client.md`; backend inspection/history/security facts to `call-inspection.md`; agent/tool/context details to their three focused references; media/opening/readiness details to their corresponding references. Keep common room command/event responsibility clear in the overview and link the precise owning contracts.

The current intended/proposed sections need verification against current source and approved amendments before being written as supported behavior. Archive original implementation-checkpoint and acceptance narratives, preserving their anchors or repairing inbound historical links. The architecture overview should not inherit every speculative future requirement merely because the old source included it.

### Operator and credential documents

`operator-api-key-authoring.md` currently combines installation keys, authoring, outgoing calls and catalogs. Its endpoint/authority/error definitions become `operator-api.md`; authoring data rules belong to `call-specs.md`; outgoing dial lifetime belongs to `telephony-calls.md`; discovery/filtering belongs to `provider-registry.md`. Keep the installation operator key distinct from tenant keys and browser sessions.

`provider-credential-storage.md` becomes the source of task steps for `guides/provider-credentials.md` and storage/reader invariants for `reference/credentials.md`. Merge Test/Save behavior into that reference; keep UI procedures and keyring rollout in the guide. Platform encryption-key rotation is a distinct guide heading, not a provider API-key operation.

### Speech APIs versus runtime versus provider specifics

Split `speech-provider-contract.md` into common/STT/TTS `speech-provider-api.md` and the STS extension `sts-provider-api.md`. Neither should repeat scoped supervision from `speech-sessions.md`, room-owned routing/history from `sts-room-lifecycle.md`, or vendor wire limits from provider pages. The authoring guide similarly splits into practical STT/TTS and advanced STS walkthroughs, both linking those contracts.

Within `sts-context-restoration.md` and `gpt-live-room-history.md`, move common room-approved history, privacy and publication barriers to `sts-room-lifecycle.md`. Google handle resumption and safe renewal live in the Google page; GPT-Live reconnect/reseed and private late results live in the OpenAI Live page. Proposed fresh-session reconstruction stays in its milestone until supported.

### Client contract versus Console implementation

The browser-client reference owns host adapters, supported protocol envelopes, revisions/tombstones and reconnect behavior. The inspection reference owns server response/completeness/security. The Console routing and React styling development pages separately own navigation/editor state and styling/build/distribution details. Operator editing/inspection remain task guides. This keeps four different readers from encountering the same repeated implementation prose.

## Refinement order and acceptance

1. Agree on the folder/page map and canonical ownership. Build the README navigation against approved destinations.
2. Rewrite setup, tenants/keys, credentials, editor and examples first, checking their commands/routes against current source.
3. Split architecture and shared speech contracts before merging narrower runtime reports; otherwise duplication carries forward into the new pages.
4. Consolidate telephony, lifecycle, policy/readiness and provider pages. Reconcile previously identified stale support/status claims against source and milestone evidence.
5. Refine contributor/test guides and archive dated measurements/implementation evidence. Repair repository links/anchors and check complete source-to-destination coverage.

This proposes documentation work, not runtime changes or paid-service execution. For eventual implementation, preserve approved contracts and historical evidence, verify examples with proportionate checks, and label supported behavior versus pending scope precisely.

## Verification of the original proposal (before approved moves)

- Re-inventoried the current working tree: exactly 69 Markdown files remain under `docs/`.
- Read current heading inventories and the existing per-file review; all 69 current paths occur in the destination map, with no nonexistent or extra sources.
- The proposal defines 40 distinct topic paths plus `docs/README.md`; 8 guides, 24 references and 8 development pages.
- The only new repository artifact in this turn is this labnote created with `bin/create-labnotes docs-organization-proposal`. Existing source documents are unmodified by this proposal.
