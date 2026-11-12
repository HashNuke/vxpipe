# Consent POST rejection

## Evidence

- The user reported the plain-text invalid authorization request after Allow in
  Chrome, using a newly generated Codex manual-login URL.
- The running QA container is named `vxpipe`, managed by `vxpipe.service`.
  Its original logs only recorded that the OAuth browser pipeline halted.
  OAuth routes suppress ordinary request logging to avoid exposing request data.
- A read-only database check showed the reported request still existed, was bound
  to the browser session, and was not expired. The controller had not consumed it.
  The release does not enable distributed Erlang, so RPC was unavailable; a short
  release eval started only Ecto SQL and the repository for this read-only check.
- Public and direct-local HTTPS assets match the checkout's current bundle. The
  bundle has the same-tab confirmation and no obsolete presentation input.
- After deploying rejection diagnostics, the user's retry logged POST, status 400,
  reason `unexpected_form_fields`. The exact extra field has not been identified.
  A hard-refresh retry was requested to check for an old browser-loaded bundle.

## Change and checks

- Keep the existing request acceptance rules. Add fixed rejection reason labels,
  method and status to warnings. Form contents, authorization identifiers, tokens,
  browser identity and URLs are not logged. Distinguish malformed forms, unexpected
  fields, missing/invalid decisions and an untrusted origin.
- Red: the new focused logging/privacy case failed because no reason was logged.
  Green: all 16 Console OAuth browser cases pass, including CSRF and rejection
  boundaries. Root format, warnings-as-errors compilation, strict Credo and unused
  dependency checks pass. No full suite was run.
- A real Chrome run with the rollback-only local CIMD fixture reaches Access
  approved and Back to my app. Rendered confirmation inspected. This did not
  reproduce the user's extra-field submission; it does not establish resolution.
- Deployed the diagnostics release, verified health and both system services.
  No environment files were read. The container remains limited to 1 GiB.
