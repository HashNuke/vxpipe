# Consolidate integration definitions

The user requested `vxpipe/integrations/` as the catalog source for the existing
`vxpipe-integrations-web` publisher. All three worktrees started clean. The
canonical GitHub source is publicly readable `HashNuke/vxpipe`, branch `main`.
Unauthenticated GitHub repository metadata confirms that visibility.

Moved sixteen definitions, contribution instructions, schema/template, validator,
five existing schema tests and icon-discovery evidence. Metadata lives below
`integrations/schema/`; the publisher imports direct `integrations/*.json` only.
Its default, environment example and Railway IaC select the new repository. The
local source example is `../vxpipe/integrations`. Updated AGENTS ownership notes
and added the path-filtered catalog validation workflow. The old repository now
redirects contributions and retains its historical files for explicit hosted
cutover; no runtime fallback or synchronization with it was added.

The initial implementation added new test scaffolding and webhook path filtering.
The user correctly asked to keep this a repository migration and carry over only
meaningful existing tests. Removed that scaffolding and extra webhook behavior.
The existing signed webhook still refreshes on all configured-branch pushes.
No new automated tests remain. The existing API test fixture merely names the
new repository. Existing copied validation tests differ only in file locations.

Verification:
- All sixteen copied definition payloads matched the originals apart from
  `$schema` before the favicon correction below.
- Existing Python validator: sixteen definitions and template valid.
- Existing five schema tests pass.
- Existing publisher `go test -race ./...`, `go vet ./...` and static server
  build pass on the final source. Existing storage Worker tests also passed.
- A real existing `directory sync` command against the new local directory
  initially refused Cal.com's stale deployment-specific favicon. Its existing
  `cmd/icons` tool discovered the current declared 512x512 PNG. Updated only that
  URL and saved the discovery evidence under `integrations/docs/`.
- Repeated the real import into an isolated local SQLite/object store: success,
  all sixteen expected slugs and one published snapshot. No hosted writes.
- The attempted broad umbrella run found an unrelated existing STS-transfer
  assertion racing outcome consumption (`:held`). The unchanged test reproduced
  it. Stopped that detour after the user's scope correction; no Elixir code or
  tests were changed, and no full umbrella pass is claimed for this migration.

Hosted cutover remains separate: deploy the publisher with the new explicit
`DEFINITIONS_REPOSITORY`, register its signed push webhook on `HashNuke/vxpipe`,
then retire the old source webhook. GitHub CLI authentication is unavailable,
so live webhook configuration was not performed. No Railway deployment or live
configuration changes were made. The detailed cutover is recorded in the
publisher's operations guide and the main source-ownership document.

## Authorized production deployment — 2026-11-10

The user subsequently authorized updating and deploying the integrations app.
Updated only the production catalog source variables to `HashNuke/vxpipe`, branch
`main`, with `AUTO_SYNC=true`. Preserved storage, credentials, the existing volume
and the publisher's own source repository. Uploaded publisher commit `2632e67`
with the Railway CLI because this service uses local uploads; Railway MCP managed
configuration and verified deployment state and runtime logs.

- Deployment `96624ef4-91a8-4237-be1e-4c54314c02bd` reached SUCCESS.
- Startup refresh completed. Health/readiness return 200, the live integration
  list contains sixteen entries, and category/search requests return 200.
- Published catalog revision changed from
  `7d5e4d161e0c03e1423f691e15adc9c67ea30cf9ad37b8d0a15ebe5cc71cba7c` to
  `924a55dfab31ad066904798ac6521678e49e9703052fa996c83bde79f112fce2`.
- A manual signed push notification for `HashNuke/vxpipe` returned 202. Logs
  confirm completion of `manual-cutover-dd2cb381-b678-4d93-afb1-269661956271`.
  This verifies the deployed receiver and queue, not delivery from GitHub.
- Browser inspection loaded the public API documentation. Chrome initially
  required `--no-sandbox` in this host environment. An initial Python urllib
  icon HEAD request returned 403; curl HEAD requests returned 200 for Cal.com,
  OpenAI and Telnyx, and Chrome rendered Cal.com's 512×512 PNG successfully.

GitHub CLI is unauthenticated and the GitHub plugin is not connected. Started
the CLI device sign-in flow with webhook administration scope and requested user
sign-in while completing deployment. Creating the new repository hook and
retiring any old hook remain pending authentication. No new tests or runtime
code were added for deployment.
