# Vxpipe

Vxpipe is an Elixir umbrella project for reusable, Membrane-backed voice call
rooms and a standalone HTTP/WebSocket service. It is both a library that other
OTP applications can embed and a release that can run independently in a
container.

Vxpipe does not use Phoenix. Do not add Phoenix, Ecto, a database, or a frontend
toolchain unless the user explicitly asks for one and the existing Plug/Bandit
architecture cannot satisfy the requirement.

## Umbrella boundaries

Keep dependencies and runtime responsibilities in the application that owns
them. The umbrella root coordinates builds and the `vxpipe` release; do not add
ordinary runtime dependencies to the root `mix.exs`.

### `apps/vxpipe`

This is the reusable, provider-neutral core library and OTP runtime.

- Own room plans, validation, participant specifications, room lifecycle,
  supervision, routing policy, events, and the Membrane media graph.
- Keep pure plan/configuration modules usable without starting processes.
- Start shared room infrastructure only: registries, task supervisors, dynamic
  room supervision, and other provider-neutral runtime services.
- Do not depend on `vxpipe_web`, `vxpipe_server`, or any provider adapter.
- Do not contain Plug routes, Bandit listeners, provider HTTP clients, provider
  webhook payloads, credentials, or product-specific persistence.

### `apps/vxpipe_web`

This is the reusable web integration library.

- Own framework-neutral Plugs, `WebSock` handlers, WebSocket upgrade logic, and
  the versioned external HTTP/WebSocket protocol.
- It may depend on `vxpipe`, Plug, WebSockAdapter, and JSON tooling.
- It must not open a listening socket. A host application must be able to mount
  `Vxpipe.Web.Router` inside its own Plug or Phoenix router.
- Keep provider-specific webhook and media ingress handlers in their adapter
  applications. Mount or dispatch to them from this layer.

### `apps/vxpipe_server`

This is the standalone composition and release entry point.

- Own the Bandit listener and server runtime configuration.
- Compose `vxpipe`, `vxpipe_web`, and the selected adapter applications.
- Keep it thin: it should configure and supervise reusable components rather
  than contain call-room domain logic.
- Preserve `/health` as a liveness check and `/ready` as a dependency-aware
  readiness check.

### Adapter applications

Telnyx, Deepgram, Rime, LLM providers, recorders, storage systems, and future
integrations are adapters. Create them as separate umbrella applications or
external packages when implemented.

- Adapter applications depend on `vxpipe`; `vxpipe` never depends on them.
- An adapter owns its provider client, wire protocol, codecs, webhook
  verification, streaming session processes, configuration schema, and error
  normalization.
- Core plans refer to provider-neutral behaviours and validated adapter
  modules. Do not make a generic human participant default to Telnyx or make a
  generic STT/TTS capability default to a particular provider.
- Map external adapter names through an explicit allowlist/registry. Never turn
  untrusted strings into module atoms.
- Declare dependencies directly in the adapter that uses them. Do not rely on
  transitive dependencies from another umbrella child.

## Runtime architecture

Model every live call as a supervised process island under
`Vxpipe.RoomsSupervisor`.

- The room controller is the control plane. It owns lifecycle, participant
  membership, authorization, subscriptions, transfers, tool/control events,
  and authoritative room state.
- A per-room `Membrane.Pipeline` is the media plane. It owns continuous audio,
  stream formats, timestamps, demand, buffering, resampling, encoding, mixing,
  recording branches, and media outputs.
- Participant and adapter workers own their own integration-specific state.
- Define failure and shutdown semantics for the entire room island. A failed
  controller, pipeline, connection, or capability must not leave orphaned
  media processes or provider sessions.
- Monitor dynamically attached workers and WebSocket outputs, and remove their
  room/pipeline state when they terminate.
- Avoid long-running work and external network calls inside room GenServer
  callbacks. Do not make the room controller a synchronous per-audio-frame
  bottleneck.
- Validate a complete room plan before spawning any part of it. If startup
  fails after processes have been created, tear down the partial room.
- Make start/end operations idempotent where provider retries or duplicate
  webhooks can invoke them more than once.

## Membrane guidelines

Membrane is the required media runtime, not a type annotation around a custom
GenServer audio loop.

- Use `Membrane.Buffer` and explicit Membrane stream formats inside the media
  graph.
- Normalize provider media at adapter boundaries. Do not carry provider JSON,
  base64 payloads, or provider codec names through the core graph.
- Preserve presentation timestamps and other timing information needed for
  live mixing, recording alignment, and latency measurement.
- Express reusable integrations as Membrane elements or bins with documented
  pad and stream-format contracts.
- Keep control events such as transcripts, participant state, and provider
  lifecycle outside the high-rate audio path. Use pipeline notifications to
  cross between media and control planes deliberately.
- Isolate each live WebSocket output branch with bounded buffering so a slow
  consumer cannot stall a room or grow a BEAM mailbox without limit.
- Explicitly decide how a branch handles lag: drop frames, disconnect the
  consumer, or apply another documented policy.
- Do not mix audio merely because multiple tracks exist. Preserve individual
  participant tracks and create mixed output only for consumers that request
  it.
- Test project-owned elements and pipelines with Membrane testing facilities
  and deterministic sources/sinks. Do not test Membrane's own implementation.

## HTTP, WebSocket, and webhook guidelines

- Use Plug for HTTP routing, Bandit for the standalone listener, and
  WebSock/WebSockAdapter for inbound WebSockets.
- Do not introduce Phoenix Channels for a raw streaming or webhook requirement
  that the current stack can handle directly.
- Treat inbound server WebSockets and outbound provider WebSocket clients as
  different concerns. Provider adapters choose and own their outbound client.
- Authenticate and authorize a live-audio subscription before upgrading the
  connection. Authorization must include access to the requested room and
  participant/mixed track.
- Prefer binary WebSocket frames for audio. Do not base64-encode audio in JSON
  unless an external provider protocol requires it.
- Version public WebSocket and webhook-facing protocols. Do not expose internal
  room topic names, process messages, or structs as an accidental wire format.
- Make read-only audio subscriptions distinct from connections that inject
  media. A media-producing socket joins as a participant connection; a
  read-only listener is an observer/output attachment.
- Configure finite frame-size, timeout, queue, and heap limits appropriate to
  the protocol.
- Provider webhook adapters must verify signatures against the exact raw body
  before trusting parsed fields. Document middleware ordering so host
  applications do not consume or replace the raw body first.
- Normalize verified provider payloads into provider-neutral Vxpipe events
  before passing them to the core.
- Account for duplicate, delayed, and out-of-order webhooks. Use provider event
  identifiers or another explicit idempotency mechanism where available.
- Return errors deliberately. Do not acknowledge a webhook as successfully
  handled when required validation or dispatch failed.

## Public library and extension API

- Keep public modules small, documented, and provider-neutral.
- Add `@spec` declarations for public functions and types for public structs,
  behaviours, plans, events, and adapter contracts.
- Prefer structs for stable domain values and tagged `{:ok, value}` /
  `{:error, reason}` results at recoverable boundaries.
- Separate pure plan construction/validation from process startup so consumers
  can reuse configuration modules without booting the standalone server.
- Accept a runtime/supervisor reference where practical instead of assuming
  one unavoidable global instance. Preserve the default supervised runtime for
  straightforward use.
- Treat adapter behaviours and plan formats as public compatibility surfaces.
  Change them intentionally and document migrations.
- Do not leak PIDs, provider credentials, raw request objects, or
  adapter-private state in public room snapshots and events.

## Single Responsibility Principle

- Give every umbrella app, module, process, supervisor, Plug, Membrane element,
  and Membrane bin one cohesive reason to change.
- Application modules compose and supervise. They must not also implement room
  policy, provider calls, protocol parsing, or media transformation.
- A room controller owns control-plane state and lifecycle. It must not buffer
  media, call providers directly, persist records, or serve web requests.
- A room pipeline owns media topology. Project-owned elements and bins should each
  perform one clear transformation or integration task.
- Adapter clients own provider transport and translation. Provider SDK structs and
  callback formats must stop at the adapter boundary.
- A webhook Plug owns raw-body capture, verification, parsing, and normalization;
  core modules own the resulting domain event and its effects.
- A WebSocket handler owns protocol lifecycle and message validation. Put audio
  buffering and fan-out in a separate bounded bridge or queue; do not combine
  authentication, codec work, mixing, persistence, and transport in one process.
- Routers dispatch. Route-specific Plugs validate and translate their own inputs.
- Avoid generic `Utils`, `Helpers`, `Manager`, or `Service` dumping grounds. Name
  modules after the responsibility they own.
- Split a module when it accumulates unrelated collaborators, unrelated state,
  separate callback families, or multiple independent reasons to test or deploy
  it. SRP does not require one function per module; keep a cohesive concept
  together.
- Test behavior at the boundary that owns it. Do not reach across umbrella apps to
  test another app's private implementation.
- Enforce the dependency direction in `mix.exs`; architectural boundaries that
  exist only by convention will eventually be crossed.

## Project hygiene

Work in small, coherent checkpoints that leave the umbrella usable. Keep the
implementation, focused tests, and relevant documentation for a checkpoint
together.

### First-time worktree setup

- Run `bin/setup` once after creating or checking out a new worktree and before
  running tests or `bin/dev` there.
- Keep `bin/setup` idempotent and update it whenever development gains another
  required setup step.
- `bin/setup` must prepare dependencies and tools but must not start long-running
  development processes; those belong in `Procfile.dev` and run through
  `bin/dev`.

Use red-green-refactor for behavior changes:

1. Write the smallest focused test that describes the desired externally
   observable behavior, then run it and confirm it fails for the expected reason.
2. Implement the smallest coherent change that makes the test pass.
3. Refactor only after the test is green, while keeping the focused test and the
   broader relevant umbrella suite green.

Do not write the implementation first and backfill tests. Documentation-only,
comment-only, configuration-only, and mechanical changes with no runtime behavior
may skip the initial red test, but still require proportionate verification.

Do not add tests for behavior guaranteed and tested by Elixir, OTP, Plug,
Bandit, Membrane, or another dependency. Test Vxpipe's contracts, integration
boundaries, supervision decisions, failure handling, and wire protocol.

For substantial research or architecture changes, add a focused document under
`docs/` that records the decision, rejected alternatives, implications, and
verification evidence. Do not create decision documents for simple status
checks or routine mechanical edits.

### Labnotes

- For research and implementation tasks, create a labnotes file with
  `bin/create-labnotes` and a two-to-four-word hyphenated task name.
- Use the resulting file under `labnotes/` as checkpoint labnotes. Update it as
  work progresses with what worked, what did not, barriers encountered,
  workarounds, decisions and their rationale, and relevant test evidence.
- Keep labnotes factual and useful to the next person resuming the task. They do
  not replace durable architecture or user-facing documentation under `docs/`.
- Do not create labnotes for simple status checks, read-only inspection, or a
  request that only runs an existing command or script.
- Labnotes are local working records and remain ignored. Never force-add or commit
  them.

### Git and commit hygiene

- Inspect `git status --short` and the relevant diffs before and after changes.
  Preserve user changes and unrelated work already in the worktree.
- Do not create commits unless the user asks. When asked, make each commit one
  coherent, usable checkpoint and include its implementation, tests,
  documentation, and relevant lockfile changes together.
- Avoid WIP, fixup, and vague commits. Use a concise imperative subject. Use the
  body to record motivation, architectural decisions, migration concerns, and
  verification when those details are not obvious from the diff.
- Stage exact paths and inspect `git diff --cached` before committing. Do not use
  broad staging such as `git add -A` in a dirty worktree.
- Commit `mix.lock` with dependency changes and the frontend package-manager
  lockfile with JavaScript dependency changes.
- Never commit credentials, webhook secrets, recorded call audio, personally
  identifiable data, local absolute paths, `_build`, `deps`, `node_modules`,
  coverage output, or release artifacts.
- Do not amend, rebase, reset, force-push, delete branches, or undo existing
  commits unless the user explicitly requests that exact operation.

## Elixir and OTP guidelines

- Never access lists using bracket/index syntax. Use pattern matching,
  `Enum.at/2`, or `List` functions.
- Do not use map access syntax on structs. Access struct fields directly or use
  the struct's public API.
- Bind the result of `case`, `cond`, `if`, and `with` expressions when the
  resulting value is needed; rebinding only inside a branch does not update the
  outer binding.
- Keep one top-level module per file. Do not nest multiple modules in one file.
- Never call `String.to_atom/1` on external input. Prefer fixed mappings or
  `String.to_existing_atom/1` only when the set is already controlled.
- Predicate functions should end in `?`; reserve `is_*` names for guards.
- Use standard `Date`, `Time`, `DateTime`, and `Calendar` functionality unless a
  genuinely unsupported parsing requirement exists.
- Give OTP supervisors and registries explicit names in child specs.
- Start dynamic room children through their `DynamicSupervisor`, not by calling
  worker `start_link/1` functions directly from arbitrary processes.
- Use `Task.async_stream/3` for bounded concurrent enumeration and choose an
  explicit timeout, commonly `:infinity` for work whose caller owns the full
  lifecycle.
- Keep GenServer calls bounded and avoid cyclic synchronous calls between room,
  participant, connection, and capability processes.
- Use `terminate/2` only for best-effort cleanup. Correctness must come from
  links, monitors, supervision, and explicit lifecycle operations.

## Dependency and Mix guidelines

- Read task documentation with `mix help TASK` before using unfamiliar Mix
  tasks or options.
- Add dependencies to the umbrella child that directly owns their use.
- For HTTP clients in provider adapters, use Req. Do not add HTTPoison, Tesla,
  or direct `:httpc` usage.
- Prefer the standard library and existing dependencies. Add a dependency only
  when it owns meaningful behavior the project should not implement itself.
- Do not use `mix deps.clean --all` as a routine troubleshooting step.
- Keep runtime environment reads in `config/runtime.exs`; do not bake secrets or
  deployment-specific addresses into compile-time configuration.
- Never commit or log API keys, webhook secrets, access tokens, signed stream
  URLs, raw authorization headers, or environment-file contents.

## Testing guidelines

- Use `start_supervised!/1` for processes started by tests so ExUnit reliably
  cleans them up.
- Do not synchronize tests with `Process.sleep/1` or assert liveness with
  `Process.alive?/1`.
- Use `Process.monitor/1` and assert the corresponding `:DOWN` message when
  testing termination.
- Use `_ = :sys.get_state(pid)` or a project-owned acknowledgement when a test
  must wait until a process has handled earlier messages.
- Test provider integrations with behaviours and deterministic fake adapters.
  Normal tests must not call real Telnyx, Deepgram, Rime, LLM, or other external
  services.
- Keep live-provider and network interoperability tests in an explicitly tagged
  integration lane that is excluded from the default suite.
- Exercise webhook handlers with the exact raw body and signature headers.
- Exercise WebSocket output teardown, authorization, bounded buffering, and
  slow-consumer behavior.
- Exercise room startup rollback and ordered teardown, not just happy-path
  snapshots.
- Keep tests in the umbrella application that owns the behavior. Run focused
  tests from that child application's directory when iterating.

## Conditional UI and Storybook guidelines

Vxpipe has no UI today. Do not add Node.js, React, or Storybook dependencies unless
a UI is explicitly requested. If a UI is introduced:

- Own it in a dedicated frontend package or umbrella application outside
  `apps/vxpipe`. Keep Node and browser dependencies out of the reusable Elixir
  library.
- Use the Node.js Storybook toolchain for React components. Pin Storybook packages
  in the owning `package.json` and commit the selected package manager's lockfile.
- Run the project-local CLI from the frontend package with
  `npx storybook dev -p 6006` and verify production output with
  `npx storybook build`. Do not rely on a globally installed Storybook executable.
  In automation, `npx --no-install storybook build` is preferred so a missing
  pinned dependency fails instead of being downloaded implicitly.
- Build and review project-owned components in Storybook before wiring them into
  pages. Every reusable component should have stories for its meaningful states,
  including default, loading, empty, error, disabled, permission-denied, and
  disconnected or reconnecting states where relevant.
- Add edge-case stories for long content, narrow viewports, slow consumers, and
  large participant sets when the component can encounter them.
- Keep stories deterministic. Use fixtures and mocked HTTP/WebSocket/provider
  boundaries; never connect to real calls, use production credentials, or include
  customer audio or personal data.
- Keep presentational components driven by props. Put live WebSocket subscriptions,
  API calls, and call-room orchestration in narrowly scoped containers or hooks.
- Add interaction tests in Storybook for meaningful user workflows, and keep unit
  and integration tests alongside the frontend behavior they cover. Stories are
  examples and visual regression inputs, not the entire test suite.
- Organize stories by Vxpipe ownership and user concepts, such as `UI`,
  `CallRooms`, and `Pages`. Do not add stories for unmodified third-party
  primitives unless they document a Vxpipe-specific contract or composition.

## Security and observability

- Treat call audio, transcripts, phone numbers, credentials, and tool results
  as sensitive data.
- Do not log audio payloads, transcript bodies, webhook bodies, prompts,
  credentials, signed URLs, or provider responses by default.
- Log stable room, participant, connection, capability, adapter, and request
  identifiers along with bounded counts, sizes, durations, and normalized
  error reasons.
- Prefix project telemetry events with `[:vxpipe, ...]` and document event
  names and measurements that form a public observability contract.
- Use sampled metrics for high-rate media events. Never emit one ordinary log
  line per audio frame.
- Use constant-time comparison helpers for signatures and tokens where
  applicable.
- Validate all externally supplied identifiers, formats, sample rates, channel
  counts, frame sizes, and adapter options before using them to construct a
  room or media graph.

## Release and deployment guidelines

- `vxpipe_server` is the only standalone release entry point. Keep the umbrella
  release rooted at `vxpipe_server: :permanent`.
- Build releases and native Membrane dependencies on the same OS, architecture,
  and ABI family as the runtime container.
- The release must bind to an explicitly configured interface and port. Local
  development may use loopback; container production normally binds to all
  interfaces behind its ingress or load balancer.
- Ensure SIGTERM results in ordered room and pipeline shutdown within the
  container's termination grace period.
- Keep liveness cheap and local. Readiness may check required runtime services
  but must remain bounded and must not perform expensive provider calls for
  every probe.

## Completion checks

For code or dependency changes, run these from the umbrella root and fix
project-owned failures before finishing:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix deps.unlock --check-unused
```

For UI changes, also run the owning frontend package's tests and lint checks, then:

```shell
npx storybook build
```

Build `MIX_ENV=prod mix release vxpipe` when release configuration, runtime
configuration, native Membrane dependencies, or application startup changes.
For documentation-only changes, verify the changed documentation and skip the
compile/test/release cycle unless the documentation embeds executable examples
or changes generated configuration.

## Current state

The project currently contains the umbrella boundaries, shared OTP
infrastructure, Membrane dependencies, reusable Plug router, Bandit server,
health/readiness endpoints, and a working release. Call-room domain modules,
the per-room Membrane pipeline, live-audio WebSocket routes, webhook adapters,
and provider adapters have not yet been implemented. Do not describe scaffold
or placeholder code as a completed integration.
