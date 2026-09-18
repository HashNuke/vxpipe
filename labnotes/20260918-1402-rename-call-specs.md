# Call Specs Rename

## Scope

- Record the manager-coordinated whole-repository rename of “Call Definitions”
  to “Call Specs”; all rename implementers were requested as GPT 5.6 Luna xhigh,
  with manager diff review and final gates.
- Keep file and folder moves in the separate path checkpoint (`56c7992`) before
  content substitutions. Update current source, product copy, examples, docs,
  Storybook, persistence, and tests in their owning checkpoints.
- Preserve historical labnote filenames and historical prose. Only repair links
  in those labnotes when they point at a current path that was renamed.
- Rename the two Call Spec tables and related columns/constraints only through a
  new reversible migration; leave existing migrations untouched. Preserve stored
  plans with a safe legacy resolved-plan reader and keep existing published JSON
  byte-for-byte exact.

## Initial inventory

The path checkpoint moved 67 files with `R100` status. Current documentation
contained the old Call Definition terminology, module names, CLI task names,
snake case identifiers, JSON keys, and `/definitions` routes. Affected current
documentation included the architecture and operator/admin docs, milestone
specifications, tenant control-plane and getting-started guides, and the
engine/console README files. Historical labnotes contain links to the moved
source, milestone, and example paths.

## Decisions

- Use `Call Spec`, `Call Specs`, `call_spec`, and `call_specs` for the product
  contract and wire-facing identifiers that represent the reusable call input.
- Use `CallSpec`, `CallSpecCompiler`, `CallSpecRevision`, `CallSpecFilter`, and
  `CallSpecs` for module references in current documentation.
- Use `vxpipe.call_spec.*` for the Mix tasks and `save_call_spec`-style names
  where current API documentation exposes the operation.
- Use `call_spec_id`, `call_spec_revision`, and `/call-specs` in current docs and
  examples of the public contract.
- Keep generic MCP/tool “definitions” terminology when it describes tool
  schemas or provider-facing definitions rather than reusable call specs.
- The path rename is reversible. Existing database migrations are untouched; a
  new reversible migration renames the two Call Spec tables plus related columns
  and constraints. A safe legacy resolved-plan reader preserves stored plans,
  while existing published JSON remains byte-for-byte exact.

## Verification

- Path checkpoint `56c7992`: 67 staged `R100` moves reviewed with matching blob
  hashes and no migration filenames changed.
- Current docs/prose pass: Call Spec terminology, module/task/API identifiers,
  `/call-specs` routes, moved current paths, and the upgrade note are updated.
- Historical labnote filenames and prose remain intact; only links to moved
  current paths are repaired. A bounded Markdown link/path check and a diff
  review for unrelated tool-definition terminology were completed.
- Bounded Markdown link/path check found no newly broken moved-path links across
  346 Markdown files; it reports one pre-existing unrelated historical labnote
  link (`20260917-1139-admin-storybook-acceptance.md` to the long-content note),
  which remains unchanged. Remaining `definition` occurrences in current docs
  are intentional generic tool/model/style-definition terminology or preserved
  historical labnote filenames and anchors; no old current source path or
  `/definitions` route remains.
- Frontend evidence from the owning agent: red GettingStarted test had the two
  expected failures, then React 35 tests and Console 133 tests across 24 files,
  Console TypeScript/lint and Storybook build passed. Static Storybook was
  inspected at 1440x1000 and 390x844 for Call Specs navigation, empty state,
  and filtered calls. Root package check and 40 package tests passed. Backend
  format, compile with warnings as errors, strict Credo, and unused-dependency
  checks passed. The first full-suite attempt (seed `394258`) exposed a
  genuine generic `Tool.definition` reflection callback regression; focused
  usage/invocation tests then passed 8/0 (seed `243136`). The next full root
  run (seed `772878`) passed MCP 37, Agent Runtime 95, Call Engine 698, Calls
  109, and Artifacts 20 tests, then found one stale Gateway assertion
  (`trusted.definition` instead of `trusted.call_spec`) and a Persistence
  compilation failure from a missing `call_spec()` helper (an old private
  `definition` helper). Both corrections were completed. The isolated migration
  up/down/up test passes.
- Final root `mix test` passed with exit 0 (seed `380964`): MCP 37/0 (3
  excluded), Agent Runtime 95/0 (4 excluded), Call Engine 698/0 (12
  excluded), Calls 109/0, Gateway 438/0 (7 excluded), Artifacts 20/0 (1
  excluded), Persistence 157/0 (11 excluded), and Console 167/0 (1
  excluded), totaling 1,721 tests, zero failures, and 39 excluded. This full
  suite ran before the final local-only restoration of generic tool-definition
  arguments. The follow-up provider `req_llm_test` and
  `tool_conversation_room_test` passed 8/0 (seed `753923`) afterward; the
  restored ReqLLM and test model-provider files match `HEAD`, so no full-suite
  rerun after that local-only restoration is claimed.
- Final mandatory static gates passed after the restoration: format,
  warnings-as-errors compile, strict Credo across 958 files (9,860
  modules/functions with no issues), and unused-dependency checks. Storybook
  cache recovery was completed by a recoverable generated-cache move and
  regeneration; a populated story rendered successfully, and the owned
  server/browser were stopped. The rename introduced no behavior changes beyond
  the reviewed compatibility additions: the safe legacy resolved-plan reader
  and the new reversible migration; existing migrations remain untouched.
