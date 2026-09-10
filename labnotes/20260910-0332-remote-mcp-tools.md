# Remote MCP tools

## 2026-09-10 — milestone start and definition boundary

- Started milestone 11 from `cf9c7e0` on `milestone/remote-mcp-tools`; the worktree
  contained only this new labnote.
- Re-read the approved milestone, call-definition tool grammar, ExMCP boundary, current
  compiler/startup path, background tool runtime, and Jido tool-binding decision before
  changing behavior.
- Rechecked the available Jido interface. Hex still reports Jido AI 2.3.0 as the latest
  release. Upstream `main` was inspected at `e3d0f7671fe1349c00d7f6918eaee95a17c4c33c`;
  `ToolSelection` still accepts only Action modules, `Config.reqllm_tools/1` still derives
  schemas from those modules, and the runner still dispatches through module `run/2`.
  The required public runtime data-tool projection/executor interface therefore remains
  unavailable. No Jido fork, private API, generated module, generic dispatcher, or second
  LLM loop was introduced.
- Red: added a focused definition test for a model-visible `customer_lookup` alias selecting
  the configured `records` MCP integration's `lookup_customer` operation. Compilation first
  failed because `ToolSelection` had no `integration` field. After the parser was green, the
  same test exercised compilation and reproduced an unhandled `FunctionClauseError` for the
  new selection type.
- Green: `ToolSelection` now accepts the closed `host` and `mcp` variants. MCP selections
  require bounded identifier-shaped `integration` and `tool` values; host selections reject
  an integration field. Endpoints, credentials, headers, and arbitrary configuration remain
  rejected as unknown definition fields. Until a scoped catalog is supplied, the compiler
  returns a normal path-specific `:call_definition_resolution_failed` error instead of
  crashing.
- Focused verification: `compiler_test.exs` passes 11 tests. The full call-engine child
  passes 182 tests with zero failures and two tagged integrations excluded; its format check
  also passes.
- The ordinary shared `_build/test` coordination socket was held by an existing long-running
  test-environment BEAM with a saturated accept queue. That process was left untouched. Test
  commands used the uncommitted temporary build path
  `/tmp/vxpipe-remote-mcp-test-build`; no build-path setting was added to source or config.
- After confirmation that no user-started Vxpipe BEAM needed preserving, the blocking
  no-start IEx process was terminated. The focused 11-test suite then passed through the
  normal shared build path, so subsequent work no longer needs the temporary path.
- Root format, warnings-as-errors compilation, and strict Credo checks pass. The root test
  alias reached PostgreSQL setup before running tests and failed because this machine's
  default server requires password authentication while no test database URL/password is
  configured. The database-free owning child suite above remains green; a disposable local
  PostgreSQL run is deferred to the milestone-wide gate.

Next: define the safe resolved MCP tool/catalog records and tenant-first whole-record
resolution, then pin only public schema/generation selectors into the immutable call plan.
Private endpoints and credentials must remain behind the runtime integration owner.
