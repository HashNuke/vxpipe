# Vxpipe

## Project hygiene

Work in small, coherent checkpoints that leave the umbrella usable. Keep the
implementation, focused tests, and relevant documentation for a checkpoint
together.

Use red-green-refactor for behavior changes:

1. Write the smallest focused test that describes the desired externally
   observable behavior, then run it and confirm it fails for the expected reason.
2. Implement the smallest coherent change that makes the test pass.
3. Refactor only after the test is green, while keeping the focused test and the
   broader relevant umbrella suite green.

Do not write the implementation first and backfill tests. Documentation-only,
comment-only, configuration-only, and mechanical changes with no runtime behavior
may skip the initial red test, but still require proportionate verification.

Do not add tests for behavior guaranteed and tested by Elixir, OTP, or another
dependency. Test project-owned contracts, integration boundaries, supervision
decisions, failure handling, and protocols.

For substantial research or architecture changes, add a focused document under
`docs/` that records the decision, rejected alternatives, implications, and
verification evidence. Do not create decision documents for simple status checks
or routine mechanical edits.

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
- Commit labnotes with the implementation or research work they document.

### Implementation milestones

- Implementation specifications and progress checklists live in
  `docs/milestones/`. Start with [the milestones index](docs/milestones/index.md),
  whose Markdown checklist gives the intended implementation order.
- Milestone filenames and titles are descriptive and unnumbered. Only the index
  owns implementation order; reordering or inserting a milestone must not require
  renaming files or changing their identities.
- Each milestone describes a runnable vertical slice, its prerequisites,
  approved contracts, implementation tasks, and automated/manual acceptance checks.
  Read its linked design sources and prerequisite milestones before implementation.
- Use Markdown task lists (`- [ ]` and `- [x]`) to track actual implementation and
  verification. A written or reviewed specification is not an implemented milestone;
  leave the index entry unchecked until the milestone's acceptance gates pass.
- Keep the milestone checklist, evidence, and index synchronized with implementation
  commits. Record blockers or approved scope changes rather than checking off partial
  work. Deferred issues do not become requirements merely by being linked.
- Review each new or materially changed milestone for missing contracts and dependency
  order. Record that design review separately from implementation progress.

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
- Never commit credentials, secrets, personally identifiable data, local absolute
  paths, `_build`, `deps`, `node_modules`, coverage output, or release artifacts.
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
- Start dynamic children through their owning `DynamicSupervisor`, not by calling
  worker `start_link/1` functions directly from arbitrary processes.
- Use `Task.async_stream/3` for bounded concurrent enumeration and choose an
  explicit timeout, commonly `:infinity` for work whose caller owns the full
  lifecycle.
- Keep GenServer calls bounded and avoid cyclic synchronous calls between
  processes.
- Use `terminate/2` only for best-effort cleanup. Correctness must come from
  links, monitors, supervision, and explicit lifecycle operations.

## Single Responsibility Principle

- Give every umbrella application, module, process, and supervisor one cohesive
  reason to change.
- Application modules should compose and supervise rather than implement
  unrelated domain, transport, persistence, and presentation concerns.
- Avoid generic `Utils`, `Helpers`, `Manager`, or `Service` dumping grounds. Name
  modules after the responsibility they own.
- Split a module when it accumulates unrelated collaborators, unrelated state,
  separate callback families, or multiple independent reasons to test or deploy
  it. SRP does not require one function per module; keep a cohesive concept
  together.
- Test behavior at the boundary that owns it. Do not reach across umbrella
  applications to test another application's private implementation.
- Enforce dependency direction in `mix.exs`; architectural boundaries that exist
  only by convention will eventually be crossed.

## Dependency and Mix guidelines

- Read task documentation with `mix help TASK` before using unfamiliar Mix tasks
  or options.
- Add dependencies to the umbrella child that directly owns their use.
- Prefer the standard library and existing dependencies. Add a dependency only
  when it owns meaningful behavior the project should not implement itself.
- Do not use `mix deps.clean --all` as a routine troubleshooting step.
- Keep runtime environment reads in `config/runtime.exs`; do not bake secrets or
  deployment-specific addresses into compile-time configuration.
- Never commit or log API keys, secrets, access tokens, signed URLs, raw
  authorization headers, or environment-file contents.

## Testing guidelines

- Use `start_supervised!/1` for processes started by tests so ExUnit reliably
  cleans them up.
- Do not synchronize tests with `Process.sleep/1` or assert liveness with
  `Process.alive?/1`.
- Use `Process.monitor/1` and assert the corresponding `:DOWN` message when
  testing termination.
- Use `_ = :sys.get_state(pid)` or a project-owned acknowledgement when a test
  must wait until a process has handled earlier messages.
- Keep external-service and network interoperability tests in an explicitly
  tagged integration lane that is excluded from the default suite.
- Keep tests in the umbrella application that owns the behavior. Run focused
  tests from that child application's directory when iterating.

## UI and browser verification

- Inspect every UI or web application change in a rendered browser. Source
  review and automated tests do not replace checking the interface itself.
- Use `agent-browser` for browser inspection. Choose headless Chrome when visual
  fidelity, layout, CSS, responsive behavior, accessibility, interactions, or
  browser APIs matter. Choose Lightpanda for faster DOM, content, navigation, or
  basic interaction checks that do not require Chromium rendering fidelity.
- Cover the relevant viewport sizes and important states in a bounded inspection
  pass. If the application cannot run or browser inspection is blocked, record
  that limitation explicitly instead of implying the UI was verified.

## Completion checks

For code or dependency changes, run these from the umbrella root and fix
project-owned failures before finishing:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix deps.unlock --check-unused
```

For documentation-only changes, verify the changed documentation and use
proportionate checks when it changes generated configuration.

## Documentation references

### Model Context Protocol

- [Jido MCP documentation](https://hexdocs.pm/jido_mcp/readme.html)
- [Jido MCP package](https://hex.pm/packages/jido_mcp)
- [Approved protocol profile](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [Official client/server conformance framework](https://github.com/modelcontextprotocol/conformance)
- [Conformance integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md)
- [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything)

### Jido

- [Jido AI documentation](https://hexdocs.pm/jido_ai/)
- [Jido AI Agent](https://hexdocs.pm/jido_ai/Jido.AI.Agent.html)
- [Jido request lifecycle and concurrency](https://hexdocs.pm/jido_ai/request_lifecycle_and_concurrency.html)
- [Standalone ReAct runtime](https://hexdocs.pm/jido_ai/standalone_react_runtime.html)
- [Jido Action documentation](https://hexdocs.pm/jido_action/)

### Pipecat

- [React SDK overview](https://docs.pipecat.ai/api-reference/client/react/overview.md)
- [React SDK components](https://docs.pipecat.ai/api-reference/client/react/components.md)
- [React SDK hooks](https://docs.pipecat.ai/api-reference/client/react/hooks.md)
- [Voice UI Kit](https://voiceuikit.pipecat.ai/)
- [Small WebRTC transport](https://docs.pipecat.ai/api-reference/client/js/transports/small-webrtc)
- [RTVI standard](https://docs.pipecat.ai/client/rtvi-standard)

### Elixir WebRTC

- [ExWebRTC](https://hexdocs.pm/ex_webrtc/ExWebRTC.PeerConnection.html)

### Caddy and Tailscale

- [Caddyfile concepts](https://caddyserver.com/docs/caddyfile/concepts)
- [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Caddy certificates on Tailscale](https://tailscale.com/docs/integrations/web-servers/caddy/caddy-certificates)
