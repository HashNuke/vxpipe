# Review MCP management

- Independent source review identified the known retained-identity reconnect gap,
  plus two defects: fresh replacements unnecessarily decrypt old ciphertext, and
  credential-bearing endpoint queries can enter public metadata columns/responses.
  Fixes and checkpoint-isolation requirements are tracked in the milestone.
- The recognized-credential query regression failed with an accepted access_token
  endpoint. The endpoint policy will preserve nonsecret query parameters and reject
  conventional credential names before discovery/check I/O. This is a named-parameter
  policy, not a claim to recognize arbitrary secrets embedded in URLs.
- Discovery foundation committed separately as `652fe779` after clean independent
  review. Production OAuth, listed templates and UI acceptance remain open.

- Retained metadata lookup first failed as an absent repository operation; it now
  reads exact-tenant metadata without decrypting either connected or revoked rows.
  Normal list/detail semantics still omit revoked rows. Sixteen store tests pass.
- Fresh replacement first failed with the old decryption error. The operation now
  checks tenant/ID/generation/status via metadata and resolves only when credentials
  are omitted for an unchanged endpoint/method. Omitted-secret repair remains an
  error; complete fresh credentials can repair a missing old key.
- Explicit reconnect initially had no operation; domain regressions now verify
  fresh credentials, revoked status, observed generation, current authority and
  unchanged endpoint/directory identity. Duplicate create proposes reconnect without
  restoring the record. The proposal regression failed with the old generic conflict.
- HTTP regressions failed with missing reconnect routing and a generic 503 for the
  proposal. Session/CSRF/write-authorized reconnect and a secret-free 409 proposal
  now pass. Static endpoint fixtures call the real Console validation/projection
  adapter; OAuth endpoint tests/fixtures remain separate for checkpoint independence.
- Query-policy tests cover case, percent encoding, bracket/punctuation variants,
  raw semicolon separators, malformed escapes and nested encoding. Harmless query
  parameters retain their exact URL. Existing crash-log query markers now use a
  permitted nonsecret parameter name so logging regressions still reach the client.
- Default suites pass: Calls 310, Console 481, MCP 154 and Persistence 474 tests,
  all with zero failures. Root format, warnings-as-errors compilation, strict Credo
  and unused-dependency checks pass. Logs use `vxpipe-management-*-suite.log`.
- Two tagged HTTP/PostgreSQL/local-MCP acceptance cases pass. Disconnect erases
  ciphertext; duplicate create leaves the row revoked; explicit reconnect preserves
  ID/namespace, increments generation and sends the fresh bearer on the wire.
  Replaying the proposal fails stale. A second case removes the old encryption key,
  proves omitted-credential replacement fails, then repairs through the HTTP API
  with new credentials encrypted under the new key. No tool is invoked.
  Evidence: `vxpipe-static-management-integration.log`.
- Exact staged review found nonempty bracket suffixes bypassing the named query
  policy (for example token[0]); the added regression failed. Validate both the
  complete normalized name and its root before a bracket suffix. The first root
  suite run was deliberately terminated when this finding arrived and is not
  acceptance evidence; rerun after final fixes/review.
- Final independent adversarial review of the exact 29-file staged checkpoint
  found no remaining blockers. Root format, warnings-as-errors compilation, strict
  Credo and unused-dependency checks passed, followed by 4,840 umbrella tests with
  zero failures (183 excluded). The existing unused-default-argument test warning
  in CallSpecDrivenCallTest remains unrelated. Evidence: `vxpipe-management-root-suite.log`.
  The subsequent OAuth checkpoint's test edits were made after the MCP lane had
  finished; they are not included in this staged checkpoint or this pass count.
