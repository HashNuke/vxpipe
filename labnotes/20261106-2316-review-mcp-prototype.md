# Review MCP prototype

- User requested small coherent commits with adversarial review and fixes before
  each commit. Selected the existing Storybook discovery/authentication changes
  as the first independent checkpoint; production work remains outside it.
- Independent GPT-6 Astra xhigh source review found two functional regressions:
  Manage URL edits reset the method without discovery; client credentials still
  validated the now-hidden authorization URL. No new privacy/security sink found
  in this local-only fixture scope. This is not a production security review.
- Red: both new transition tests failed for the reported behavior (local log
  vxpipe-prototype-review-red.log). Enabled discovery and shared inline status
  in Manage, guarded unresolved saves, reset discovery on Manage/reconnect entry,
  and limited authorization URL validation to the code grant.
- Added a regression for manual endpoint/scope edits made while discovery is
  pending; the existing edited-field tracking already preserves both.
- Green: all 108 prototype tests and all 967 Console frontend tests pass;
  TypeScript and focused ESLint pass. The root static gates and full umbrella
  suite pass, including 2292 Call Engine, 870 Gateway and 464 Console tests.
- Chrome inspection at desktop and 390x844 verified custom connect, Manage URL
  rediscovery, selected CIMD and reachable Save/Disconnect/Close controls. Save
  continued into the simulated authorization screen. Browser automation had
  stale element references during hot reload; fresh DOM inspection resolved it.
- Independent re-review found both code issues resolved and no remaining scoped
  code/security findings. Removed an absolute temporary log path identified in
  its labnote hygiene check. Exact staged checkpoint review precedes commit.
