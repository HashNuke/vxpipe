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

## Shared HTTP and Identity first slice

- Inventory covers all UI product requests, including services, roles, keys,
  onboarding/sample writes and artifact links, plus explicit auth/media exceptions.
  Independent review corrected a stale claim: spec update existence checks already
  live in Calls and should be reused rather than reimplemented.
- Identity composition moved to its own runtime configuration; Console delegates.
  Two new configuration-boundary tests failed first, then 61 Identity and eight
  Console tests passed. Independent review found no remaining composition issues.
- Canonical spec-write tests first failed with 401/no CSRF enforcement. Configured
  browser authentication now resolves a session and applies CSRF before calling
  the same authoring operation used by API keys. Explicit headers never fall back.
- Reviewer identified `:forbidden` mapping to 503. Added restricted-session test,
  confirmed the failure, then mapped it to 403; all 14 endpoint tests now pass.
- Editor write URL test failed on `/admin/api`, then passed after routing writes
  through `/api`. All five adapter tests, TypeScript and assets build passed.
- Headless Chrome inspected desktop and 390px mobile using a sandbox fixture.
  Renaming and Save as draft produced canonical PUT 201 and revision 2. The first
  fixture lacked catalog repository configuration; supplying the real local port
  resolved that setup issue. Browser and sandbox process were closed afterwards.
- Full root suite overlapped agents' intentional red tests and a pending migration;
  its result cannot establish a stable green snapshot. Will rerun after the agents
  finish. Avoid concurrent migrations and sandbox browser transactions: an open
  browser transaction blocked the digest-index migration until fixture shutdown.

## Public ExMCP integration probe

- Gateway now declares its direct ExMCP dependency using the same git pin already
  in the shared lock. Outbound MCP remains independent.
- Three public-boundary tests first failed on the missing probe handler and then
  passed. They exercise actor callbacks, initialize/notifications/ping/tools,
  key-bound sessions, DELETE and monitored timeout cleanup without a network server.
- The pinned 2025 profile requires sessions; stateless behavior selects a different
  protocol revision. Wrong-key reuse deliberately returns 404. Product wrapper
  still needs strict version/method rules, Bearer auth, limits and real mounts.
- Independent review found no blockers and confirmed the limited evidence scope.
