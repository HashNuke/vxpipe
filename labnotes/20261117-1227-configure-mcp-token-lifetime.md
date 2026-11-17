# Configure platform MCP token lifetime

- Follow-up to live lifecycle validation: user requested a configurable 60-minute
  access-token lifetime and verification with the actual Codex client. They also
  reported similar Railway MCP logins expiring.
- Added runtime environment setting `VXPIPE_MCP_ACCESS_TOKEN_TTL_SECONDS`, default
  3600 and accepted range 1..86400. Both Boruta client policy and persisted token
  issuance use the same application value. Existing tokens retain their expiry;
  the grant still bounds access expiry and remains 30 days.
- Red: 17 focused tests, five expected failures for absent runtime configuration
  and the previous 599-second response. Green: 17 tests, zero failures. Checks
  cover runtime default/override/invalid inputs, exchange/refresh expiry and grant
  cap. Invalid environment values are not included in error messages.
- Documentation and environment example explain renewal, persisted rotation,
  serialization and the distinction between MCP sessions and OAuth credentials.
- Local Codex CLI is 0.169.0. Generated its app-server JSON schemas and prepared a
  persistent app-server driver for OAuth login and direct MCP calls, without
  requiring model inference. Only a temporary MCP server entry is supplied via
  process-local configuration overrides; the configured Railway server is disabled
  only for this test subprocess.
- Railway finding: this workspace's configured entry is stdio `railway mcp`.
  Its installed npm wrapper reports that the underlying CLI binary is missing.
  This is a startup issue, not evidence of refresh-token expiry, and may differ
  from the user's other Codex installations. No Railway settings were changed.
- A second temporary admin uses a freshly generated random password; cleanup is
  prepared before authorization. The previous validation admin is already archived.

## Actual Codex evidence before deployment

- Codex 0.169.0 app-server performed CIMD browser authorization as the temporary
  admin. `mcpServer/tool/call` for read-only `list_role_options` succeeded.
- Shortened only that user's current access token in the database to now plus
  60 seconds, leaving Codex's cached expiry untouched. A later call through the
  same app-server succeeded without reauthorization. Database readback showed
  the original refresh token consumed and a successor issued on the same,
  unrevoked grant. This exercises reactive refresh after server-side expiry.
- Stopped only the temporary app-server subprocess, started a fresh one, and
  called the tool using persisted credentials without login. Shortened the new
  access token and repeated: call succeeded, the second refresh token was consumed,
  and a third token existed on the same unrevoked grant.
- Therefore the tested CLI/app-server build supports both reactive renewal and
  persistence across client-process restarts. This does not establish behavior
  of a different desktop/IDE build or multiple simultaneous clients sharing a
  refresh credential. Asked which surface exhibits the user's prompts.
- Corrected adjacent user-guide consent instructions to match the browser-tested
  same-tab callback redirect; the former intermediate confirmation screen is gone.
- Two actual Codex app-server processes shared the same saved test login, loaded
  it before expiry, then made simultaneous tool calls after the test access token
  expired. Both calls and both follow-up calls succeeded. Database readback showed
  rotated tokens and an unrevoked grant. The direct Python replay/concurrency
  failure did not reproduce with these Codex processes; keep that distinction.
- User confirmed the affected surface is Codex CLI and clarified that Railway is
  context only. Do not repair or reconfigure Railway.

## Deployment recovery diagnosis and fix

- Deployed the configurable lifetime through systemd; release runtime readback
  returned 3600. The same pre-deployment Codex process's next tool call hung and
  exceeded the scratch controller's 90-second wait, while the grant stayed valid.
- A fresh Codex process reused the saved login and renewed automatically. Its
  database token lifetime was 3599 seconds, confirming the deployed 60-minute
  setting without another browser consent.
- Root cause: ExMCP's protocol validation used the latest version when session
  lookup found no record. Codex's supported 2025-06-18 header then produced 400
  before the session-existence check could produce the required 404. Python used
  2025-11-25, so its initial restart test did not expose this mismatch.
- Existing termination tests retained the session record and its protocol version,
  so they passed. Added a regression for a genuinely absent session with Codex's
  header: red 19 tests/1 failure (400 versus 404). Added a negative unsupported-
  version case during refinement; it first failed and then passed.
- Narrow dependency patch preserves the missing-session result through header
  validation while keeping unsupported headers at 400. No durable session store,
  protocol upgrade, auth bypass or refresh-replay grace period was introduced.
- Added a separate checksum manifest/patch and generalized the existing installer
  to apply both reviewed patches. A source-preservation test first failed because
  the installer ignored the new file; all 10 shell tests now pass. All 47 platform
  MCP tests pass. The pinned dependency revision and mix.lock are unchanged.
- Initial umbrella result: all applications passed except one Telnyx transfer
  timeout. The five selected cases passed with the original seed 558777; the full
  Gateway suite then passed 887 tests with that seed. Final full checks were
  repeated after the additional dependency fix and passed. A superseded intermediate run was
  stopped when the unsupported-header regression was added.
- Build correction: an initial release command ran in the main checkout and was
  stopped; its output was not deployed. QA was explicitly rebuilt and packaged.
  QA setup preserved existing environment settings, and only task-owned files
  were copied from main. Restart uses systemd to avoid the earlier second restart.

## Patched live recovery

- Applied the final protocol patch to the QA dependency, compiled it into the
  release, rebuilt the image and restarted through systemd. The existing Codex
  app-server called `list_role_options` successfully immediately before and after
  deployment. It was not restarted, reconfigured or reauthorized between calls.
- This contrasts with the pre-patch deployment hang and verifies that correcting
  the 400/404 distinction enables actual Codex session recovery. Public health
  returned 200; the 60-minute token setting remains deployed.
- Final combined live test passed: the same Codex process recovered after the
  patched deployment, then renewed another deliberately expired access token.
  The successor had a 3599-second persisted lifetime and the original grant
  remained active until cleanup.
- Second temporary admin archived; zero unrevoked browser sessions and OAuth
  grants remain. Account navigation redirected to login. Browser and temporary
  Codex subprocesses were stopped; host/container credential files were removed.
- Default Codex logout reported an unavailable keyring deletion. Repeated logout
  with a process-local `mcp_oauth_credentials_store="file"` override succeeded;
  private inspection confirmed no temporary server entry remains in the fallback
  file store. No persistent Codex or Railway configuration was changed. All test
  credentials had already been revoked server-side.

## Final verification

- Final umbrella run: 5,459 tests, zero failures (388 excluded). Gateway passed
  all 889 tests. Formatting, warnings-as-errors compilation, strict Credo and
  unused-lockfile checks passed. All 10 patch-installer tests passed.
- Task-owned source, regression tests, patches, documentation and labnotes were
  synchronized to QA. Vitrum runs the verified patch and 3600-second setting.
- User requested committing and pushing these changes to both main and QA;
  unrelated existing documentation edits are excluded from this checkpoint.
