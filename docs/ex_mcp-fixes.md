# ExMCP fork fixes

Status: all fix branches and the `vxp` integration branch are published at
`HashNuke/ex_mcp`. Vxpipe consumes `vxp` through its public HTTPS URL and locks commit
`0bfd0ae`.

## Purpose

Vxpipe uses ExMCP rather than maintaining a second MCP client. ExMCP 1.3.0 and upstream
`master` at `56880c6` need five compatibility fixes for Vxpipe's remote-client profile. The
fixes live as independently reviewable branches so they can be contributed upstream, while
`vxp` merges every required fix for Vxpipe to use until compatible upstream releases exist.

The fork does not expand Vxpipe's selected protocol profile. Vxpipe still targets MCP
`2025-11-25` over remote Streamable HTTP and must pass its own conformance and security gates.

## Repository and branch policy

- `upstream` points to `azmaveth/ex_mcp`; `master` follows upstream without Vxpipe patches.
- `origin` points to the `HashNuke/ex_mcp` fork.
- `chore/format-acp-tests` is the prerequisite pull request that makes upstream `master` pass
  its configured repository-wide format gate before any functional fix is proposed.
- Each `fix/*` branch contains one upstreamable concern and its focused tests.
- `vxp` is the integration branch used by Vxpipe. It retains merge commits so the source of
  each patch remains visible.
- Vxpipe consumes the public HTTPS Git URL and `vxp` branch. `mix.lock` pins the exact commit;
  deployments must not depend on a developer's local checkout or SSH credentials.
- Upstream changes are merged into `master` and then into the affected fix and integration
  branches without rewriting published history.

Published branches, all derived from upstream `56880c6`:

| Branch | Change commit | Published tip | Responsibility |
| --- | --- | --- | --- |
| `chore/format-acp-tests` | `75d1c6b` | `75d1c6b` | Format two upstream ACP tests required by the repository's own pre-commit gate. |
| `fix/per-client-http-security` | `cbd06dc` | `e9ebab9` | Apply each HTTP client's exact-origin security policy to credential forwarding and user resolution. |
| `fix/safe-client-diagnostics` | `570f631` | `662ad75` | Summarize client/transport failures without rendering nested response, credential, or tool data. |
| `fix/http-response-correlation` | `8ae7684` | `1dc9ce2` | Reject synchronous HTTP results and errors whose JSON-RPC ID does not match the request. |
| `fix/sse-fragment-parser` | `12ee528` | `c2222f6` | Preserve incomplete SSE bytes across arbitrary TCP chunk boundaries. |
| `fix/request-scoped-sse-budgets` | `8add24c`, `261bc90` | `261bc90` | Enforce request-scoped budgets across complete SSE events and recovery; remove an unreachable fallback found by Dialyzer. |
| `vxp` | — | `0bfd0ae` | Merge the prerequisite and all five fixes for Vxpipe consumption. |

## Upstream pull-request order

Submit the changes in this order:

1. `chore/format-acp-tests` targets upstream `master`. Submit and merge this mechanical change
   first so every later branch passes ExMCP's configured pre-commit commands without bypassing
   the format gate.
2. `fix/per-client-http-security` is independent and can target the newly formatted upstream
   `master`.
3. `fix/safe-client-diagnostics` is independent and can target upstream `master`.
   It may be reviewed in parallel with the security fix, but keeping it immediately after that
   fix keeps the upstream discussion to one security boundary at a time.
4. `fix/http-response-correlation` is independent and targets upstream `master`. It establishes
   that synchronous HTTP responses belong to the request before their result or error is accepted.
5. `fix/sse-fragment-parser` targets upstream `master`. It establishes correct incremental
   parsing before response accounting relies on complete event boundaries.
6. `fix/request-scoped-sse-budgets` depends on the parser fix. Open it against the parser
   branch while that pull request is pending, or wait for the parser pull request to merge
   and then target upstream `master`. Do not present the parser changes twice in review.

If upstream asks for a different decomposition, preserve these concern boundaries in the
fork even if the upstream pull requests are reorganized. Never merge `vxp` itself upstream;
it is the downstream integration branch.

## Fix behavior

### Per-client HTTP security

Two clients may trust different exact origins without a process-global union. Credential
headers remain available only to the origin trusted by that client state. The application
configuration remains a default, and the client configuration overrides it at the effective
HTTP request boundary.

### Safe client diagnostics

Failure logs retain the operation and the failure's structural shape, but not nested remote
values. Tool names in invalid header annotations are fingerprinted. Returned protocol data
is unchanged; this fix concerns logs, not application error normalization.

### Synchronous HTTP response correlation

Every synchronous JSON-RPC result or error must carry the exact ID generated for its request.
A response with another ID is rejected as `:response_id_mismatch` with non-retryable delivery
semantics. Retrying is unsafe because the server may already have performed the requested action;
accepting the unrelated response would attribute another operation's outcome to the caller.

### Fragment-safe SSE parsing

The streaming parser emits only blocks terminated by an unambiguous SSE blank line and
returns the untouched incomplete suffix. Tests split one CRLF-framed event at every byte
boundary, including inside field names, JSON data, and line endings.

### Request-scoped cumulative response budgets

Modern request-owned streams count all complete event `data` bytes in their own process.
Legacy shared streams carry decoded-message byte counts to the client, which associates final
responses by JSON-RPC request ID and progress events by progress token. Counters survive SSE
worker reconnection and are removed on response, cancellation, timeout, or connection loss.

An exhausted correlated budget fails only the matching request with
`:response_too_large`. Uncorrelated traffic has a separate bounded allowance; exhausting it
closes the connection rather than assigning those bytes to an arbitrary request. SSE data in
the request's POST response and later GET-stream events share the same request budget.

## Verification evidence

- Per-client security: 14 focused tests and 109 transport tests passed.
- Safe diagnostics: 33 focused client tests passed; the private response sentinel was absent
  from captured logs.
- Synchronous response correlation: all 12 focused result-validation tests passed, covering both
  result and error envelopes with mismatched request IDs.
- SSE parsing: 12 parser tests and 52 related stream tests passed.
- Request budgets: 57 focused client/HTTP/SSE tests passed.
- Integrated `vxp` at `0bfd0ae` passes every configured ExMCP pre-commit command:
  repository-wide formatting, warnings-as-errors compilation, Credo, Dialyzer, and the staged
  skip-tag guard. The focused fix suites also pass.
- Vxpipe's lockfile resolves the public `vxp` branch to `0bfd0ae`. Its default MCP suite
  passes 32 tests, including exact endpoint-origin construction, request progress-token
  transmission, and cumulative enforcement after `Last-Event-ID` recovery while the
  resumed stream remains open.
- The pinned official initialization and tool-call scenarios pass 1/1 each, the corrected
  recovery scenario passes 3/3, and the pinned Everything server returns the expected
  `echo` tool result through Vxpipe's wrapper.
- The full upstream suite ran 4,622 tests with two failures unrelated to the modified MCP
  paths: a locally available Claude authentication-method list differed from the fixture,
  and the modern stdio fixture could not resolve the `:jason` SCM in its generated Mix
  project.
- The formatting prerequisite passes its complete pre-commit hook and 155 focused ACP tests. The
  subsequent response-budget cleanup also passed the complete hook before it was committed. Every
  published fix branch now contains the prerequisite, and the `vxp` superset passes the same full
  hook commands without exceptions.

## Removal policy

Keep using the fork until an upstream release includes equivalent fixes and passes every
Vxpipe acceptance gate. Then replace the Git dependency with that Hex release, regenerate
the lockfile, run the official conformance, Everything-server, recovery, credential-isolation,
diagnostic-privacy, and cumulative-budget checks, and only then retire the fork dependency.
Do not carry duplicate downstream patches after the compatible release is adopted.
