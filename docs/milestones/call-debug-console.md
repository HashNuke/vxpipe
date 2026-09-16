# Call debug console

Status: planned, not implemented. Requested 2026-09-16; local specification review recorded below.
Prerequisites: [Prepared calls](prepared-call-admission.md), [Call inspection](call-inspection-and-debugging.md),
[Tenant credentials](tenant-provider-credentials-and-platform-configuration.md), and the implemented
[human-transfer](human-web-transfers.md) / [readiness](transfer-readiness-and-wait-sounds.md) contracts.
Pending live-carrier acceptance is not required to build this browser surface.
Sources: [Developer console design](../developer-console-and-onboarding.md),
[Gateway/Console boundary](../gateway-console-boundary.md), [Operator's Bench](../../DESIGN.md).

## Runnable outcome

A developer selects a published definition route in their tenant and uses chat history/composer
or realtime voice in the same call. Agent audio and streaming text appear together, with currently
spoken text highlighted when supported timing permits it. Metrics, logs, device controls,
participant identity and transfer progress make the run understandable. Results remain visible
when the call ends. The same console will run Getting Started examples.

## Contracts

- Console owns `/debug` and `/debug/calls/:call_id` in its existing React/esbuild composition.
  Keep two independently extractable source boundaries from the first slice: framework-neutral
  client JS and React components. The Console app composes them and owns routes/auth/setup.
- The client public interface owns normalized snapshots/subscriptions, lifecycle/commands,
  protocol/media capabilities, device controls, metrics, protocol-event records and spoken progress.
  Keep RTVI/Vxpipe decoding and WebRTC integration behind distinct adapter contracts. The
  existing Pipecat client-js/Small WebRTC pair is sufficient; no new real adapter is required.
- React components use only the public Vxpipe client API and injected host data/actions. No
  direct RTVI decoding, RTCPeerConnection, Pipecat-specific React hooks/types, tenant API fetches
  or Console imports. Client has no React/Phoenix/app dependency; shared public types belong
  to client exports. Component styles/theme must work outside the current application shell.
- Console provides admission/inspection through adapters/callbacks. Neither reusable boundary
  hard-codes sample/setup URLs or requires platform/tenant/provider keys. Ephemeral admission
  credentials never enter public snapshots/logs. Cleanup is client-owned, not dependent on
  a React component staying mounted. Reuse working SDK behavior behind these boundaries.
- Use existing tenant authentication for the first slice. Tenant `calls` authority permits
  authorized preparation/inspection; definition administration still requires its own `admin`
  authority. A bounded safe published-route listing needs an explicit Calls authorization
  contract; it must not expose private source merely to populate a selector.
- Browser session authentication is server-side; no tenant/platform/provider secret is passed
  to the SDK. Every call selection, preparation, inspection and secondary-seat action checks
  tenant/call authority. Public IDs and join tokens do not establish operator access.
- Chat history/composer, metrics, logs and voice-device controls are core UI requirements.
  Typed and realtime voice input share one call/participant; text works without microphone
  permission. Stream generated agent text while audio plays, including audio replies to typed
  messages when enabled/available. Preserve existing turn/interruption semantics.
- Spoken-text highlighting requires explicit word/segment alignment capability, correct output/
  turn identity and usable playback timing. Keep generated, emitted and confirmed played states
  distinct; current segment progress does not prove word-level remote playout. Without alignment,
  show streaming text plus a speaking indicator/confirmed progress. Never simulate a word cursor.
- Metrics reuse available call/provider timing and reported usage, plus bounded client transport
  statistics. Label source/units/unknowns and respect clock domains.
- Logs contain only sent/received RTVI events, including Vxpipe extensions inside RTVI. Exclude
  application/server logs, browser console output, transport lifecycle diagnostics, private
  inspection records and the separate transfer sideband. Filter by event type/direction and
  available identity; retain observed order and repeated traffic, with safe event details.
  Client-owned protocol-event records keep RTVI decoding out of the reusable React viewer.
- Device controls include input/output choice where supported, microphone/speaker mute and
  activity/connection state. Unsupported speaker selection has a clear system-device fallback.
- Keep standard RTVI and existing versioned `vxpipe.turn`/`vxpipe.transfer` envelopes compatible.
  Human acceptance remains on the existing separately parsed `vxpipe` sideband.
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
  for future client-JS/React extraction without introducing package publishing now.
- [ ] Red-test client lifecycle/events without React and components against a fake public client.
  Enforce dependency/import boundaries; substitute a fake adapter without changing components.
  Review the initial rendered composition within Operator's Bench.
- [ ] Red-test an authorized published route, one deliberate start, duplicate/ambiguous preparation,
  microphone denial and transport failure. Include unauthorized/cross-tenant and draft-route denial.
- [ ] Implement call header, selected definition/revision, chat history/composer, realtime voice
  control, input/output devices, microphone/speaker mute, leave and an enduring run-result view.
  Typing uses the existing send-text command; microphone consent is separate from text input.
- [ ] Red-test typed input with no microphone permission, realtime voice, both within one call,
  duplicate/failed sends, draft preservation, device loss and unsupported output-device selection.
- [ ] Show streaming agent text while hearing audio. Red-test supported word/segment highlighting
  and no-alignment fallback, including interruption and stale progress for an earlier output.
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
- [ ] Add dedicated Metrics and Logs views, selected-event inspector and read-only definition view.
  Reuse available timing/usage and bounded browser statistics; Logs filter only RTVI events.
  Link to existing authorized history for durable facts instead of inventing another log store.
- [ ] Test populated/partial/unavailable metrics, sources/units/clock differences, bounded log
  volume/filtering/pause behavior and cleanup of stats polling/listeners when a connection closes.
- [ ] Verify RTVI extensions appear in Logs while server/browser logs, inspection records and
  transfer-sideband messages do not. Correlate by actual event/turn/attempt identity, retain
  provenance, and mark non-comparable timing and trimmed browser events honestly.
- [ ] Verify refreshing a run cannot claim/replay a consumed session, duplicate commands, start
  another room or silently lose the result. A fresh run is a deliberate new preparation.
- [ ] Inspect 360/768/1440 px, light/dark, keyboard/focus, reduced motion, long identifiers,
  2/6 participants, high event volume, device-denied, waiting, failed and ended states.
- [ ] Switch `/pipecat-console` to the verified replacement and keep the transfer desk usable.
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
- [ ] Logs display RTVI events only, including versioned Vxpipe server-message extensions.
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
The user's logs clarification limits the Logs panel and event details to RTVI traffic. Server,
browser, inspection and separate transfer-sideband logs are excluded; existing history stays linked.
No implementation, rendered UI, independent-agent review or acceptance is claimed by this plan.
