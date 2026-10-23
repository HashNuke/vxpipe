# Simplify transfer rows

- The outgoing-call story showed a participant-type subtitle under each allowed transfer destination. This was generated as Human destination or Agent; saved participant descriptions were already hidden.
- Removed that redundant line and centered the participant name with its remove control. Missing-participant feedback remains available for broken references.
- Extended the existing transfer-search test to reject both type subtitles, observed its expected failure, and updated the stale Storybook assertion that still expected a description.
- Verification: all 98 frontend test files / 769 tests pass; TypeScript, ESLint and production CSS build pass. Rendered the compact transfer row at desktop and mobile sizes. Root format, warnings-as-errors compilation, strict Credo and unused-dependency checks passed again. The prior complete umbrella run passed all 3,811 reported tests; the backend has not changed since that run.

## Frontend/backend review before committing

- Reviewed all pending frontend changes, including picker state, catalog parsing, naming and source edits, edit-only options, read-only states, issue focus, Storybook fixtures, checkbox state, transfer rows and section permission layout.
- The picker requires the new tool_catalog lookup payload. Its backend projection is included: platform definitions, registered host actions, and the effective tenant MCP catalog; no connection secrets or network discovery are exposed. Existing controller serialization carries the field without a new route. Frontend/backend tests cover the matching payload.
- The MCP registration key reaches the existing compiler and model descriptor unchanged; the remote MCP name is retained separately for invocation. The compiler regression test covers records__lookup_customer. Per-tool blocking/non-blocking values already exist in ToolSelection, ToolBinding and runtime invocation contracts; omitted mode defaults to blocking on both sides.
- Include all persists each selected tool explicitly. The backend already compiles an explicit per-agent map, so future MCP tools are not implicitly granted. Existing saved aliases/visibility remain intact on mode-only edits.
- Transfer subtitle removal, permission alignment, clock tooltips, compact dialogs and fixture corrections are presentation changes and require no backend schema or migration changes. Existing permission enforcement remains in place.
- No additional backend changes were needed beyond the catalog projection and contract tests included with the frontend feature. The API projection and its consuming UI will be committed together.

- Final copy refinement: removed “in to” from the outgoing request destination hint. This changes only explanatory text; the existing request destination contract is unchanged.
- Updated the call-variable helper to the user’s requested “This is the information your agents collect. Configure access in each agent’s Variables tab.” This is also copy-only.
- Final copy verification: the human-inspector and variable-panel suites pass (27 tests). No backend change is required for either text refinement.
