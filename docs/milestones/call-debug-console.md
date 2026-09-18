# Call debug console

Status: private-package Storybook prototype and database-backed production inspection host available;
live call interaction is not implemented.
Requested 2026-09-16; local specification review recorded below.
Prerequisites: [Prepared calls](prepared-call-admission.md), [Call inspection](call-inspection-and-debugging.md),
[Tenant credentials](tenant-provider-credentials-and-platform-configuration.md), and the implemented
[human-transfer](human-web-transfers.md) / [readiness](transfer-readiness-and-wait-sounds.md) contracts.
Pending live-carrier acceptance is not required to build this browser surface.
Sources: [Developer console design](../developer-console-and-onboarding.md),
[RTVI call-variable projection](../rtvi-call-variable-projection.md),
[debug-console metrics](../debug-console-metrics.md),
[call-details model](../debug-console-call-details-model.md),
[Gateway/Console boundary](../gateway-console-boundary.md), [Operator's Bench](../../DESIGN.md).

## Runnable outcome

A developer selects a published call spec route in their tenant and uses chat history/composer
or realtime voice in the same call. Agent audio and streaming text appear together, with currently
spoken text highlighted when supported timing permits it. Metrics, logs, device controls,
participant identity and transfer progress make the run understandable. Results remain visible
when the call ends. The same console will run Getting Started examples.

## Contracts

- Console owns `/tenants/:tenant_key/calls/:call_id/console` in its existing React/esbuild
  composition, with its database inspection resource beside it at
  `/tenants/:tenant_key/calls/:call_id/inspection`.
  Use `packages/core` (`@vxpipe/core`) and `packages/react` (`@vxpipe/react`) as independent npm
  packages from the first slice. Keep them private until publication is separately requested.
  The Console app composes them and owns routes/auth/setup; Storybook lives with React.
- The client public interface owns normalized snapshots/subscriptions, lifecycle/commands,
  protocol/media capabilities, device controls, metrics, protocol-event records and spoken progress.
  Keep RTVI/Vxpipe decoding and WebRTC integration behind distinct adapter contracts. The
  existing Pipecat client-js/Small WebRTC pair is sufficient; no new real adapter is required.
- Keep the serializable call-details record, its incremental update reducer, and browser-local
  media/command state separate. The Console host fetches authorized baseline/history payloads for
  ongoing and ended calls and hands them to the normalized Core store through an initial snapshot
  and injected refresh/pagination callbacks. Core/React do not fetch tenant endpoints. An attached
  RTVI session contributes only the ongoing call's live edge. Stable entity IDs plus increasing
  revisions own replacement; explicit tombstones own removal. Reject stale-incarnation updates,
  expose known sequence/archive gaps, and request a fresh host-supplied baseline after unsafe
  continuity. A read-only ongoing or ended source renders the same tabs without fabricating live
  controls or requiring the operator to join the call.
- React components use only the public Vxpipe client API and injected host data/actions. No
  direct RTVI decoding, RTCPeerConnection, Pipecat-specific React hooks/types, tenant API fetches
  or Console imports. Client has no React/Phoenix/app dependency; shared public types belong
  to client exports. Author component styling with Tailwind v4 utilities and semantic CSS
  variables under the [React styling contract](../react-component-styling.md). The npm build emits
  compiled CSS; shadcn registry items install the same editable TSX source and required tokens.
- Console provides admission/inspection through adapters/callbacks. Neither reusable boundary
  hard-codes sample/setup URLs or requires platform/tenant/provider keys. Ephemeral admission
  credentials never enter public snapshots/logs. Cleanup is client-owned, not dependent on
  a React component staying mounted. Reuse working SDK behavior behind these boundaries.
- Use existing tenant authentication for the first slice. Tenant `calls` authority permits
  authorized preparation/inspection; call spec administration still requires its own `admin`
  authority. A bounded safe published-route listing needs an explicit Calls authorization
  contract; it must not expose private source merely to populate a selector.
- Browser session authentication is server-side; no tenant/platform/provider secret is passed
  to the SDK. Every call selection, preparation, inspection and secondary-seat action checks
  tenant/call authority. Public IDs and join tokens do not establish operator access.
- Chat history/composer, variables, metrics, logs and voice-device controls are core UI requirements.
  Typed and realtime voice input share one call/participant; text works without microphone
  permission. Stream generated agent text while audio plays, including audio replies to typed
  messages when enabled/available. Preserve existing turn/interruption semantics.
- Keep the full configured participant roster in the sidebar before, during and after a call.
  Presence/activity is a separate projection: configured, inactive or departed participants remain
  selectable with muted styling and never acquire a fabricated `waiting` state. Sidebar selection
  opens the Participants tab.
- The Participants tab shows the selected participant's authorized configuration: capabilities,
  system prompt, transfer policies and available tools. This is tenant-authorized debug/operator
  data, not an ordinary participant or public RTVI projection. Omit denied fields and label an
  unavailable configuration; never infer configuration from live presence or emitted events.
- Spoken-text highlighting requires explicit word/segment alignment capability, correct output/
  turn identity and usable playback timing. Keep generated, emitted and confirmed played states
  distinct; current segment progress does not prove word-level remote playout. Without alignment,
  show streaming text plus a speaking indicator/confirmed progress. Never simulate a word cursor.
- Metrics reuse available call/provider timing and reported usage, plus bounded client transport
  statistics. Model room, room-capability, participant and participant-capability scopes; expose
  turn measurements beside the corresponding message only when correlation is authoritative.
  Group the hover detail into whole-turn and available LLM, input-guardrail, output-guardrail,
  TTS and STT steps. Support reported response duration, TTFT, TPOT, TPS, RTF and
  audio-to-first-audio measurements where they make sense; omit absent groups and values rather
  than synthesizing them. Label source/units/unknowns and respect clock domains.
- Treat TTS request-to-first-decoded-audio as time to first audio, not audio-to-first-audio. A2FA
  spans authoritative speech end to correlated server audio egress and does not claim browser
  playback or remote audibility. Recognized-audio duration is STT usage, not transcription latency.
  The approved boundaries, formulas, current evidence and implementation gaps are in
  [debug-console metrics](../debug-console-metrics.md).
- Conversation is one ordered timeline with icon filters for messages, semantic events, tool calls
  and raw logs. Messages, events and tool calls are enabled by default; raw logs are disabled, and
  Reset restores those defaults. Join/leave/transfer facts are concise activity rows, not a separate
  status bar. Raw logs contain only sent/received RTVI events, including Vxpipe extensions. Exclude
  application/server logs, browser console output, transport lifecycle diagnostics, private
  inspection records and the separate transfer sideband. Filter by event type/direction and
  available identity; retain observed order and repeated traffic, with safe event details.
  Client-owned protocol-event records keep RTVI decoding out of the reusable React viewer.
- Tool calls disclose captured request and response data through tabs in one responsive panel.
  An HTTP-backed tool may include its response status for completed or failed calls. Preserve the
  difference between unavailable capture and an explicitly empty argument/body payload.
- Device controls include input/output choice where supported, microphone/speaker mute and
  activity/connection state. Unsupported speaker selection has a clear system-device fallback.
- Keep standard RTVI and existing versioned `vxpipe.turn`/`vxpipe.transfer` envelopes compatible.
  Human acceptance remains on the existing separately parsed `vxpipe` sideband.
- Project authorized call variables as complete, revisioned `vxpipe.variables` version 1 snapshots
  inside RTVI `server-message`. Send a race-free baseline on debug-seat readiness and the newest
  snapshot after accepted updates. Ordinary participant admission never receives unrestricted
  values; the browser cannot elevate projection visibility. React consumes normalized Core state.
- Document the minimal authoritative roster and output-attribution projection before adding
  wire fields. Ordinary bot output currently has no participant ID. Define source event identity,
  call/incarnation, baseline/revision, recipient visibility and gap/resync semantics. Unknown
  or stale data is labeled; it never assigns a speaker by guessing the current active agent.
- Keep participant-visible protocol facts separate from tenant-authorized private inspection.
  Reuse Calls live/history projections and pagination; add no Repo access or arbitrary process
  state inspection. UI slowness cannot back-pressure room/media work.
- Retain the ended/disconnected run on screen. Leave disconnects the local seat; end-call is a
  different action and only appears if an existing authorized command supports it. No automatic
  reconnect with consumed credentials, command replay, microphone capture or duplicate call creation.
- Match the component/layout proposal in the design source; rendered review confirms the actual
  composition. This milestone does not create a visual editor, raw payload export or new media engine.

## Checkpoint 1 — Start and understand one call

- [ ] Record/review the client public API, separate protocol/media adapters, capabilities and
  import rules, plus the safe tenant route-selection/preparation boundary. Keep source isolated
  in the confirmed Core/React workspaces without introducing package publishing now.
- [x] Red-test and implement the normalized call-details store before a real adapter: live semantic
  upserts, duplicate/stale revisions, tombstones, call-incarnation rejection, deterministic order,
  cursor-page overlap, completeness/gaps, and reconnect baseline replacement. Keep raw RTVI receipt
  logs append-only and keep local device/control state outside the serializable call record.
- [x] Feed equivalent remote ongoing, attached-live and remote ended fixtures through that store
  and render the same Conversation, Variables, Metrics, and Participants data. The Console host
  fetches the authorized Calls inspection snapshot and immutable database resolved plan
  revision, then injects that baseline; RTVI contributes only attached-live
  updates. Unavailable or redacted data stays distinguishable from captured empty values.

### Checkpoint 1A — Assemble one complete database snapshot

- [x] Red-test one authorized query that first resolves the call, then loads its complete persisted
  `CallHistory`, immutable prepared call/resolved participant plan and persisted usage report. The
  result has no pagination cursor and no response-generation timestamp.
- [x] Treat "complete snapshot" as all history currently persisted in PostgreSQL. Preserve the
  archive's `complete`, `incomplete` or `unconfirmed` state; the endpoint never implies that an
  ongoing or interrupted asynchronous archive has finished.
- [x] Keep the call history and immutable prepared plan essential. Usage failures remain explicit
  partial availability; a missing/cross-tenant call, plan or history fails the snapshot.
- [x] Prove through the injected backend and source review that this query never invokes live-room inspection,
  call-details publications, recordings, artifact storage or S3.

Exit: one typed query result contains every database record needed by the response and no transport
or presentation fields. Commit this slice with its focused query tests.

### Checkpoint 1B — Convert the snapshot to the public response

- [x] Red-test a pure `CallInspectionPresenter` that converts the typed query result into versioned
  snake-case JSON. It performs no I/O and does not know about Plug, Phoenix or repositories.
- [x] Project lifecycle, configured participants, messages, semantic events, complete tool-call
  request/response state, latest variables, usage metrics and archive completeness. Preserve
  captured empty values versus unavailable data; do not expose tenant keys, credential selectors,
  source policies or arbitrary call spec source.
- [x] Remove `older_cursor` and `as_of` from this endpoint contract and from the matching Core
  baseline. Stable database identities and revisions still support later RTVI updates.

Exit: fixture database records encode to the complete client snapshot and round-trip through JSON.
Commit this slice with presenter tests and the synchronized Core contract.

### Checkpoint 1C — Expose the authorized HTTP resource

- [x] Add `GET /tenants/:tenant_key/calls/:call_id/inspection` under the existing operator session and `calls` authority.
  The controller only invokes the query and presenter, maps missing/cross-tenant calls to the same
  `404`, maps invalid requests to `400`, and maps database unavailability to `503`.
- [x] Return JSON with `Cache-Control: private, no-store`. Red-test ongoing and ended calls,
  authentication, response content type, error mapping and absence of secret/session reflection.
- [x] Prove the endpoint performs no live-room, publication, recording, artifact or S3 operation.

Exit: an authenticated browser can fetch one latest complete database snapshot for a call. Commit
this slice with focused endpoint tests.

### Checkpoint 1D — Connect the Console host to Core

- [x] Add a Console-owned runtime validator/mapper for the JSON response and inject the resulting
  Core snapshot into the debug console. Core and React do not fetch the route directly.
- [x] Red-test ongoing, ended, unavailable and malformed responses. Refresh replaces the complete
  database baseline; an attached RTVI adapter may contribute only newer live updates.
- [x] Render the same remote ongoing and ended states through the real host adapter and inspect the
  bounded desktop/mobile states in Chrome.

Exit: the production Console route renders a database-loaded call through the same reusable store
and React components used by Storybook. Commit this slice with TypeScript and browser evidence.

### Remaining call-start and interaction work

- [ ] Before adding more components, migrate the prototype from its monolithic selector stylesheet
  to Tailwind v4 utilities plus semantic theme tokens. Build npm CSS from the same source and prove
  one clean shadcn-registry fixture installation; do not maintain two component implementations.
- [ ] Red-test client lifecycle/events without React and components against a fake public client.
  Enforce dependency/import boundaries; substitute a fake adapter without changing components.
  Review the initial rendered composition within Operator's Bench.
- [ ] Red-test an authorized published route, one deliberate start, duplicate/ambiguous preparation,
  microphone denial and transport failure. Include unauthorized/cross-tenant and draft-route denial.
- [ ] Implement compact call controls, chat history/composer, realtime voice
  control, input/output devices, microphone/speaker mute, leave and an enduring run-result view.
  Typing uses the existing send-text command; microphone consent is separate from text input.
- [ ] Red-test typed input with no microphone permission, realtime voice, both within one call,
  duplicate/failed sends, draft preservation, device loss and unsupported output-device selection.
- [ ] Show streaming agent text while hearing audio. Red-test supported word/segment highlighting
  and no-alignment fallback, including interruption and stale progress for an earlier output.
- [ ] Red-test and implement the read-only Variables tab from normalized snapshots, including
  baseline/update/reconnect ordering, stale revisions, unavailable state and structured values.
- [ ] Preserve connection versus capability readiness, interim/final text and generated/emitted/
  played distinctions. Missing timing stays unavailable; no guessed current-word highlighting.
- [ ] Prove a real SDK connection and one conversation using controlled existing adapters, plus
  a bounded rendered desktop/mobile pass. Preserve the current sample until this path works.

Exit: an existing tenant can complete and inspect one call without the new onboarding/platform key.

## Checkpoint 2 — Understand participants and handoffs

- [ ] Audit existing events, then document and review only the missing roster/attribution projection
  needed for the UI, including versioning, baseline/resync, visibility and source correlation.
- [ ] Red-test two agents, a caller and a human destination, including output around a handoff,
  interleaved participant events, late/stale incarnation messages and denied private content.
- [ ] Implement participant rail and attributed conversation using authoritative identities;
  distinguish configured, present and left participants from browser transport connections.
- [ ] Red-test and implement the persistent configured roster plus Participants tab. Selecting a
  muted, active or departed participant opens the same stable identity and renders only the
  authorized capability, prompt, transfer-policy and tool projection. Keep WebRTC/phone connection
  media separate from configured capabilities: audio input and room output are runtime media
  demands, while STT remains an optional participant capability.
- [ ] Show current transfer attempt/phase/blockers from existing events. Offer the existing support
  seat in a separate view with explicit media consent and its bound acceptance-ready control.
  Displaying or selecting a participant must not secretly join or monitor them.
- [ ] Verify unknown extension versions preserve the ordinary call, old attempts cannot enable
  acceptance, and unmodified supported SDK clients retain their existing behavior.
- [ ] Run one existing agent-handoff and one human-acceptance browser scenario with correct
  identities/readiness. Reuse existing call-flow evidence; no new transfer behavior is required.

Exit: a developer can follow who is in the call and who spoke across existing handoffs.

## Checkpoint 3 — Diagnose and finish a run

- [ ] Red-test bounded RTVI event retention, repeated traffic, observed order, paused-follow,
  unavailable history links and an ended call with no live room.
- [ ] Add the scoped Metrics view and the Conversation timeline's raw-log filter/selected-event
  inspector, plus the read-only call spec view. Reuse available timing/usage and bounded browser
  statistics; raw Logs items include only RTVI events.
  Link to existing authorized history for durable facts instead of inventing another log store.
- [ ] Red-test and implement call-scoped metric observations for model-attempt duration/first
  visible text, TTS duration/first audio, whole-turn duration/A2FA and STT final-transcript latency.
  Preserve call,
  participant, turn trigger/origin, capability-attempt, outcome, provenance and clock boundaries;
  keep existing identity-free operational telemetry in parallel. Do not relabel agent-session
  request telemetry as provider-attempt timing.
- [ ] Red-test the authorized live/history metric projection and versioned debug-seat transport.
  Ordinary participants must not receive private metric or usage facts. Join existing attributed
  token/audio usage only by exact attempt/turn identity and matching semantics, then derive TPOT,
  TPS and RTF where their required inputs are compatible.
- [ ] Red-test bounded browser WebRTC-stat polling, selected-connection changes and cleanup. Label
  RTT/jitter/loss as browser transport measurements and never present them as remote audibility.
- [ ] Test populated/partial/unavailable metrics, sources/units/clock differences, bounded log
  volume/filtering/pause behavior and cleanup of stats polling/listeners when a connection closes.
- [ ] Verify RTVI extensions appear in Logs while server/browser logs, inspection records and
  transfer-sideband messages do not. Correlate by actual event/turn/attempt identity, retain
  provenance, and mark non-comparable timing and trimmed browser events honestly.
- [ ] Verify refreshing a run cannot claim/replay a consumed session, duplicate commands, start
  another room or silently lose the result. A fresh run is a deliberate new preparation.
- [ ] Inspect 360/768/1440 px, light/dark, keyboard/focus, reduced motion, long identifiers,
  2/6 participants, high event volume, device-denied, waiting, failed and ended states.
- [ ] Switch `/samples/pipecat-console` to the verified replacement and keep the transfer desk usable.
  Update source-development/sample docs, affected diagnostics links and component evidence.

Exit: a usable, bounded debug console remains informative through failure and completion.

## Acceptance and completion

- [ ] Tenant isolation and participant/operator projection separation hold at every new boundary.
- [ ] Client JS has no React/app dependency; React consumes only its public, protocol-neutral
  contract. Console-specific auth/routes/setup stay outside both extraction boundaries. Import
  checks, framework-free client tests and fake-client component tests prove the separation.
- [ ] Standard RTVI plus Vxpipe extensions work over the existing WebRTC adapter; a fake protocol/
  transport substitution leaves UI components unchanged. No new real transport or SDK fork.
- [ ] Chat history/composer accepts typed and realtime voice input in one call; the developer
  hears agent audio while text streams, with supported spoken-word/segment highlighting or a
  truthful fallback. Metrics, logs and device controls work without assuming mic/output support.
- [ ] Raw log timeline items display RTVI events only, including versioned Vxpipe
  `server-message` extensions.
- [ ] One authorized call, multi-agent handoff and human acceptance work through the same console;
  refresh/leave/end states preserve correct authority and useful evidence.
- [ ] No secret, signed URL or unrestricted private payload enters URLs, client configuration,
  browser persistence, console logging or a participant projection.
- [ ] Focused child tests, TypeScript/component checks and all common umbrella gates pass.
  Real provider/network interoperability belongs in the tagged integration lane.
- [ ] Rendered browser evidence covers the stated sizes/states using `agent-browser`.
- [ ] Update this checklist, the index and checkpoint labnotes in small passing commits.

## Manual acceptance

Use a synthetic tenant with existing Google/Deepgram-compatible fixtures. Start by typing with
microphone disabled and hear/see the streamed reply, then explicitly enable realtime voice within
the same call. Verify supported spoken-text progress and the no-alignment fallback. Inspect Metrics,
Logs and device controls, the identified participants and one selected event; complete existing
agent and human handoffs, deny a second seat access, disconnect, and reopen the authorized result. Repeat with
microphone denial and an unavailable inspection source. A controlled provider failure must leave
an actionable result; it must not turn a stored credential into a claimed successful provider test.

## Specification review

Local design review, 2026-09-16: independent of the future platform key; reuses existing Calls
admission/inspection and transfer sideband; identifies the real missing bot-output attribution
contract; bounds diagnostics and preserves authorization, cleanup and SDK compatibility. The
user's follow-up explicitly includes chat/composer, text and voice input, simultaneous streaming
text/audio, capability-driven spoken highlighting, metrics, logs and device controls. These are
covered in runnable checkpoints and acceptance rather than deferred to a future UI polish task.
The next user clarification requires future client-JS and React packages. The plan now isolates
those layers from the first runnable slice, separates protocol from media transport, hides SDK
implementation details and tests substitution without requiring another real adapter or publication.
The user's logs clarification limits raw Conversation log items and event details to RTVI traffic.
Server, browser, inspection and separate transfer-sideband logs are excluded; existing history
stays linked. A later clarification removes the separate Logs tab in favor of the filterable
Conversation timeline and places semantic participant activity inline.
The metrics clarification separates whole-turn measurements from optional LLM, input-guardrail,
output-guardrail, TTS and STT step groups. It names the initial reported measurements without
requiring every provider or call path to supply every group or value.
This specification review did not claim implementation, rendered UI or acceptance; prototype
evidence is recorded separately below.

### Storybook prototype follow-up

The subsequent user request moves source isolation into actual npm packages named `@vxpipe/core`
and `@vxpipe/react`. The [prototype](../../packages/README.md) provides a typed Core boundary and
fixture-backed React views, with dark as default. Preview states belong to Storybook; remove
redundant headings, notices, tenant and transport labels from the call canvas. These are prototype
artifacts, not passing production checkpoints: real adapters, admission and browser media remain
unchecked. Application-specific Getting Started fixtures are outside reusable package exports.

The latest review places call actions above compact microphone/input and speaker/output groups,
using icon toggles and bordered selectors. Streaming output uses sequential dots before its time.
Shadcn source distribution is feasible; the design source records the proposed package follow-up
and consumer verification. It is not implemented or counted as production acceptance here.

The participant follow-up keeps the configured roster visible in muted form before presence and
adds the fourth Participants tab. The prototype shows authorized capabilities, system prompt,
transfer policies and tools for a selected roster identity. This remains fixture-backed; the
private call spec projection and live roster adapter are still production checkpoint work.
