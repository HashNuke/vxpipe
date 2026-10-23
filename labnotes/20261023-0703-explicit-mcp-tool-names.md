# Explicit MCP tool names

## Request and decisions

- Refined the existing add-tools implementation: group built-ins and MCP integrations, expose remote tools only after choosing an MCP, include all current tools explicitly, remove generated aliases, and support per-tool and bulk conversation modes.
- Researched the official MCP tool-name rules and Claude Code permission naming. MCP requires uniqueness within a server, but does not mandate a cross-server prefix. Adopted Claude Code's `mcp__<server>__<tool>` convention, using the configured integration name as the server qualifier. Built-in and host names remain their registered names. Sources and rationale are recorded in `docs/call-spec-editor-guide.md`.
- Rejected arbitrary numeric suffixes and truncation because they make prompt references unpredictable. A collision or qualified name beyond the existing 128-character identifier limit fails without partially applying a batch.
- Preserved existing saved aliases when editing options, since automatically renaming historical source could invalidate prompt references. Choosing a replacement uses its canonical name and remaps visibility overrides.
- Include all is a selection of current eligible catalog entries, including entries hidden by search; no wildcard is persisted and later catalog additions remain excluded. Existing enabled tools cannot be removed through the add flow.
- Each selected MCP tool has its own non-blocking control. The common mode selector applies to the selection and shows Mixed when choices differ.
- Storybook uses only the real built-ins `get_current_time` and `hangup`; fake registered host tools stay in focused test doubles. Sample MCPs provide 12 integrations and 18 calendar tools to exercise scrolling.

## Implementation and verification

- Initial red tests reproduced missing grouping boundaries, include-all selection, canonical names, collision rejection, and per-tool modes before implementation. A later focused red test covered clearing Include all when a catalog name collides with an existing saved entry.
- The compiler test confirms that the model receives `mcp__records__lookup_customer` while the MCP binding retains remote name `lookup_customer`. No runtime compiler change was required; the spec key already flows into the model tool descriptor.
- TypeScript and ESLint passed. The full frontend suite passed: 98 files, 764 tests. After the short-viewport and unavailable-name refinements, TypeScript, ESLint and all 31 tests in the three focused tool-editing suites passed again (including the new collision/Include-all case).
- Rendered inspection used headless Chrome through agent-browser, dark desktop 1440×1000 and light mobile 390×844, with an additional 320×568 stress case. Covered grouped lists, search, partial/all selection, per-tool mode/Mixed, and long lists.
- Desktop modal bounds were identical before/after choosing an MCP: x=384, y=148, width=672, height=704. Mobile bounds were also identical: x=16, y=70, width=358, height=704. Both lists had content taller than their viewport and no horizontal overflow.
- The bounded design pass found two issues: partial selection looked like a full tick, and the shortest viewport squeezed the checklist. Fixed the shared indicator to show a minus for indeterminate state; added a minimum usable list area with scrollable options and a stable footer. At 320×568 the final modal stays within the viewport, with a 130px checklist and 69px footer. Desktop/mobile confirmation captures are temporary artifacts, not repository assets.
- Confirmation also scrolled the calendar checklist to its final tool and added the real `hangup` built-in through the full call-editor page. The enabled-tools panel showed the exact saved name afterward. No new design suppressions were needed, and the inspection browser was closed after verification.
- `bin/setup` was attempted but the existing local Postgres endpoint stalled during authentication. Used a private, disposable UTF-8 PostgreSQL cluster on a Unix socket for tests. It does not listen on TCP and does not read provider credentials. Storybook remains directly managed on port 6006, without tmux.
- Root format, warnings-as-errors compilation, strict Credo, and unused dependency checks passed. The full umbrella suite passed: 3,811 tests, zero failures (configured integration/live exclusions remain excluded).

## Completion

- Stopped and removed the disposable PostgreSQL cluster after the suite passed. Closed the inspection browser. Storybook remains directly managed on port 6006.
- No commits were created. Existing unrelated worktree changes were preserved.
