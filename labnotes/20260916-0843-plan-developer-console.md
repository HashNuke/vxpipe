# Plan developer console

## Request and scope

Plan a Vxpipe debug console first, followed by platform-level API-key access, demo tenant,
STT/TTS/LLM provisioning, installed definitions and a Getting Started home. Planning only;
no implementation, new provider authentication or release work is authorized by these documents.
The prior request for small coherent commits applies to this planning checkpoint.

The user's follow-up confirms `/` remains setup tracking plus links to individually ready samples.
One image defaults to production behavior, with explicit demo opt-in. Proposed spelling is
`VXPIPE_DEMO=1`, unset/blank/0 off. It changes presentation/demo routes, not MIX_ENV, authentication,
TLS, keyring protection or database selection. Disabling retains saved resources and admitted calls.

## Inspection and decisions

- Started with a clean worktree. Existing `/` is a Vxpipe directory, not Phoenix boilerplate.
- The current React voice page uses Pipecat ConsoleTemplate and loses the visible run on disconnect.
  Human acceptance already has a separate `vxpipe` sideband. Reuse both transports and current SDKs.
- RTVI codec advertises 2.1.0 and already has versioned vxpipe.turn/vxpipe.transfer messages. Ordinary
  bot-output does not carry participant identity, so explicit attribution/roster projection is a
  real design gate; never infer every utterance belongs to the current agent.
- Existing Calls.Principal is tenant-bound (admin/calls). A platform key needs a distinct principal
  and trusted local first issuance. No anonymous first-visitor claim or globalized tenant key.
- Reuse private Calls live/history inspection through existing authorization; do not leak those
  facts into participant RTVI or duplicate archival storage.
- Existing SampleCall startup saves/publishes and issues a sample key. New durable example setup
  must replace this managed seeder, with explicit adoption and per-example version mapping.
- Deepgram can supply STT and TTS through one stored binding; Google is the first model choice,
  with current Zenmux alternative. No S3/phone/MCP requirement for first voice use.
- Added three ordered specifications: debug console (3 checkpoints), platform bootstrap/demo
  tenant (2), Getting Started/examples (3). Packaging and retention remain held and follow them.
  Index becomes 29 specifications/22 complete/7 incomplete; no implementation box checked.

## Design and reference use

Used impeccable shape guidance and existing DESIGN.md Operator's Bench. Read product context,
React/CSS and home/transfer/inspection ownership. PRODUCT.md includes stale early implementation
prose; source/completed milestones govern this plan, and unrelated context files were not rewritten.
The proposal makes conversation primary, participants persistent, diagnostics secondary, and call
results persistent after disconnect. No new visual identity or pixel-level approval is claimed.

Checked official Pipecat RTVI, React SDK and Small WebRTC documentation. The public RTVI page has
historical version wording; local negotiated version/tested shapes remain authoritative. Official
React composition and custom server-message support informed the plan without a dependency upgrade.
A few guessed source filenames were absent; follow-up file inventory located the actual
Administration/Principal/LiveCallInspection modules. No implementation depended on those guesses.

## Local specification review

Reviewed runnable slices, prerequisite order, platform versus tenant/participant authority,
secret input/output, source-of-truth readiness, disabled direct routes, retry/restart/idempotent
example installation, preservation of edited definitions, event identity/gaps, browser boundaries,
and the existing delivery hold. Removed a speculative general call-request idempotency subsystem:
the debug UI must reconcile ambiguous outcomes without automatic retries instead.
Review is local; no independent-agent implementation or UI verification is claimed.

## Verification

Documentation verification passes across seven changed Markdown files: 139 local links/anchors,
balanced fences, 29 unique sequential index entries (22 complete, 7 incomplete), ordered new
prerequisites and 3 + 2 + 3 new runnable checkpoints with implementation boxes unchecked.
The first pass caught a missing platform-bootstrap specification-review anchor; split that
heading and reran successfully. The checker also needed to accept the index's valid directory
link, not only files. Local review covers the changed delivery prerequisite/mode contract.
No runtime, UI, dependency, env.sample or database file is changed; full Mix/browser suites are
not applicable to this planning-only checkpoint. Staged whitespace verification passes.

## Explicit console requirements from follow-up

Added chat history/composer, metrics, logs and device controls as core acceptance. Typed input and
realtime voice share a call; typing must work without microphone permission. Agent audio plays
while text streams. Highlight current words/segments only with supported, correctly correlated
alignment and playback evidence; the existing codec's segment progress does not prove word timing
or remote audibility. Use an honest speaking/progress fallback rather than a generated word cursor.
Metrics reuse existing timing/usage and bounded transport statistics. The subsequent user
clarification restricts Logs to RTVI traffic only, including Vxpipe server-message extensions.
Removed application/server/browser diagnostics, private inspection and separate transfer-sideband
events from that panel. Preserve repeated wire events and keep existing history separately linked.
No new TTS integration or system-wide observability project was added.

## Extractable client and React boundaries

The user intends separate client-JS and React packages later. Planned isolated source roots/public
exports and import checks from the first slice: protocol-neutral client lifecycle/events/media, RTVI/Vxpipe protocol
adapter, WebRTC transport adapter, React components using only public client types and actions,
and a separate Console host for auth/routes/admission/inspection/setup. Pipecat client-js remains
an adapter implementation; reusable React cannot depend on Pipecat-specific hooks or wire types.
Acceptance will test the client without React and the UI against a fake client; a fake adapter
must prove substitution without implementing a second real transport. No package publishing or
new plugin registry is required.
