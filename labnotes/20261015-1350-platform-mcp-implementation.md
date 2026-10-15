# Platform MCP implementation

## Starting state and authorization

- User authorized the complete nine-checkpoint milestone, small commits, subagent
  reviews and concise pushnotify progress updates. Existing planning documents are
  included in the first reviewed baseline commit; implementation stays unchecked.
- Working on branch `mcp`. `bin/setup` passed dependencies, assets and dev/test
  migrations. Local Console port 4002; no live credentials were read or tests run.
- Initial pushnotify delivery command completed successfully.
- Planning subagent confirmed scope and dependency direction, and identified
  ambiguous HTTP scope errors versus MCP domain errors. Clarified the boundary:
  shared policy handles pre-dispatch key scope denial; resource visibility and
  ordinary domain failures retain safe tool errors.
- First implementation slice consolidates spec writes over a canonical HTTP
  handler with browser-session/CSRF and API-key adapters. Parallel work inventories
  all UI routes and relocates Identity dependency composition to its owner.
