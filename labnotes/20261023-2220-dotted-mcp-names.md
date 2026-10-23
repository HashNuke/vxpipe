# MCP tool registration names

- User requested canonical MCP names in the form `calendar.find_slots` instead of `mcp__calendar__find_slots`.
- Inspected the editor, call-spec validator, runtime descriptor, and ReqLLM request projection before making runtime changes. Dots are currently rejected by several project validators and by the installed ReqLLM 1.22.0 tool constructor.
- ReqLLM's `valid_name?/1` requires a leading ASCII letter or underscore, followed by letters/digits/underscores with optional single-hyphen-separated segments, and limits names to 64 characters. The runtime's request projection calls `ReqLLM.Tool.new!/1`, so a dotted name would fail before a provider request.
- Claude's current tool definition documentation also excludes dots (`^[a-zA-Z0-9_-]{1,128}$`). MCP's allowed name syntax does not imply that every model's function-calling API accepts that syntax.
- Initially asked whether automatic provider-boundary translation would be acceptable, since the earlier user requirement excluded internal aliases. The user instead selected double underscores and asked why the `mcp__` prefix was needed. It is not required; the final convention is `<integration>__<tool>`, such as `calendar__find_slots`, with no extra prefix or provider translation.
- Relevant sources: https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools and https://req-llm.hexdocs.pm/ReqLLM.Tool.html#valid_name?/1. The local installed source is authoritative for the pinned ReqLLM version.

## Implementation

- New MCP registrations combine the configured integration and exact remote tool name with double underscores. Built-in names remain unchanged. Existing saved names stay intact when editing options, avoiding changes to prompt references.
- Per the user's clarification, step one shows built-in tool names and MCP integration names. Step two shows only that MCP's original tool names, descriptions and selection/mode controls. Removed the extra qualified-name line from the modal. The enabled-tools list shows the saved qualified name for prompt references.
- A subsequent user clarification removed the duplicate shared conversation-mode control from the MCP checklist. Each tool now owns its Non-blocking checkbox; unchecked is blocking. Single-tool options remain per-tool. Updated the focused behavior test and Storybook play assertions before implementing this change.
- New MCP registration names are checked against the installed ReqLLM format and 64-character limit before adding them; the picker explains unavailable names and excludes them from Include all. Collision detection still rejects ambiguous names without generating aliases or partially applying a batch.
- The separate ReqLLM upgrade is owned by another agent. Our initial dependency fetch failed on a locked transitive requirement before the user redirected it; the other agent subsequently updated the manifests, lockfile and installed library. No further dependency changes were made here. The upgraded library's name validator remains the same.

## Verification

- Red: nine focused naming/registration assertions failed before implementation. Green: all 33 focused tests passed. The modal clarification then produced a focused failing test for the unwanted qualified-name line before it was removed.
- Final frontend suite: 98 files, 767 tests passed. TypeScript and ESLint passed.
- Compiler boundary test passed: `records__lookup_customer` reaches the runtime descriptor unchanged, while the remote MCP name remains `lookup_customer`.
- Root formatting, warnings-as-errors compilation, strict Credo and unused dependency checks passed. Full umbrella suite passed: 3,811 tests reported, zero failures (134 excluded), using an isolated disposable PostgreSQL database to avoid concurrent agents' test databases. Stopped and removed that owned cluster after the suite finished.
- Storybook initially returned a stale Vite optimized-dependency 504 after other dependency work. Restarted our directly managed Storybook process on port 6006; the modal renders normally again. Database cleanup completed; Storybook remains directly managed on port 6006.

## Compact tool controls follow-up

- User requested MCP picker labels as `calendar (18)` on one line, and enabled tool rows as `platform · get_current_time` with edit/delete on the right. Removed duplicate names/source details and the separate mode line; blocking tools have a hand icon with a hover/focus tooltip.
- User narrowed Edit tool to conversation mode only. Added a dedicated compact edit dialog and removed replacement navigation from the add flow. Saved tool identity, aliases and visibility remain unchanged by mode edits.
- Vertically centered section permission labels with their dropdowns in the agent Variables tab, as requested.
- Red tests observed the old count format, missing blocking indicator, replacement button and old focus target. Focused checks and rendered inspection follow below.

- Browser verification exposed a mode edit moving its row to the end, and a focused follow-up found a built-in mode leaking to later MCP selections. Red tests reproduced both; same-name updates now preserve row order and all add-modal modes are stored per tool.

- User subsequently selected Lucide `RotateCwFadingClock` instead of the hand. Changed only the glyph; Blocking hover/focus text and behavior stay the same.

- The edit dialog identifies MCP tools as `calendar · find_slots`, per the final user clarification. The saved registration name remains unchanged.

- Removed the “dial-routing” helper note entirely at the user’s request. Confirmed the existing rule in backend `protected_dial_section/4` and frontend `dialReference`: a number-from-variable binding prevents agent write grants to its entire section. No permission rule changed.
- Final checks: 98-file frontend suite passed (768 tests), followed by all 44 focused tests after mode-isolation/order preservation and label refinements; TypeScript and ESLint passed. Root formatting, warnings-as-errors compile, strict Credo, umbrella tests and unused-lock checks all passed.
- Rendered review covered dark desktop (1440×1000) and light mobile (390×844): inline MCP count, single-line enabled tool rows with right-side controls, Blocking hover tooltip, compact mode-only edit dialog with `calendar · find_slots`, and centered variable permission labels. The clock icon replaced the hand after the user refined the design. No unrelated typography changes or design suppressions were made.
