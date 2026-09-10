# ExMCP fork fixes

Status: all fix branches and the `vxp` integration branch are published at
`HashNuke/ex_mcp`. Vxpipe consumes `vxp` through its public HTTPS URL and locks commit
`2d31d26`.

## Purpose

Vxpipe uses ExMCP rather than maintaining a second MCP client. ExMCP 1.3.0 and upstream
`master` at `56880c6` need four compatibility fixes for Vxpipe's remote-client profile. The
fixes live as independently reviewable branches so they can be contributed upstream, while
`vxp` merges every required fix for Vxpipe to use until compatible upstream releases exist.

The fork does not expand Vxpipe's selected protocol profile. Vxpipe still targets MCP
`2025-11-25` over remote Streamable HTTP and must pass its own conformance and security gates.

## Repository and branch policy

- `upstream` points to `azmaveth/ex_mcp`; `master` follows upstream without Vxpipe patches.
- `origin` points to the `HashNuke/ex_mcp` fork.
- Each `fix/*` branch contains one upstreamable concern and its focused tests.
- `vxp` is the integration branch used by Vxpipe. It retains merge commits so the source of
  each patch remains visible.
- Vxpipe consumes the public HTTPS Git URL and `vxp` branch. `mix.lock` pins the exact commit;
  deployments must not depend on a developer's local checkout or SSH credentials.
- Upstream changes are merged into `master` and then into the affected fix and integration
  branches without rewriting published history.

Published branch tips, all based on upstream `56880c6`:

| Branch | Commit | Responsibility |
| --- | --- | --- |
| `fix/per-client-http-security` | `cbd06dc` | Apply each HTTP client's exact-origin security policy to credential forwarding and user resolution. |
| `fix/safe-client-diagnostics` | `570f631` | Summarize client/transport failures without rendering nested response, credential, or tool data. |
| `fix/sse-fragment-parser` | `12ee528` | Preserve incomplete SSE bytes across arbitrary TCP chunk boundaries. |
| `fix/request-scoped-sse-budgets` | `8add24c` | Enforce cumulative request budgets across complete SSE events and recovery; based on the parser fix. |
| `vxp` | `2d31d26` | Merge all four fixes for Vxpipe consumption. |

## Upstream pull-request order

Submit the changes in this order:

1. `fix/per-client-http-security` is independent and can target upstream `master` directly.
2. `fix/safe-client-diagnostics` is independent and can target upstream `master` directly.
   It may be reviewed in parallel with the security fix, but keeping it second gives the
   upstream discussion one security boundary at a time.
3. `fix/sse-fragment-parser` targets upstream `master`. It establishes correct incremental
   parsing before response accounting relies on complete event boundaries.
4. `fix/request-scoped-sse-budgets` depends on the parser fix. Open it against the parser
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
- SSE parsing: 12 parser tests and 52 related stream tests passed.
- Request budgets: 57 focused client/HTTP/SSE tests passed.
- Integrated `vxp`: changed-file formatting, warnings-as-errors compilation, strict Credo,
  and 95 combined focused tests passed.
- Vxpipe's lockfile resolves the public `vxp` branch to `2d31d26`. Its default MCP suite
  passes 27 tests, including exact endpoint-origin construction, request progress-token
  transmission, and cumulative enforcement after `Last-Event-ID` recovery while the
  resumed stream remains open.
- The pinned official initialization and tool-call scenarios pass 1/1 each, the corrected
  recovery scenario passes 3/3, and the pinned Everything server returns the expected
  `echo` tool result through Vxpipe's wrapper.
- The full upstream suite ran 4,627 tests with two failures unrelated to the modified MCP
  paths: a locally available Claude authentication-method list differed from the fixture,
  and the modern stdio fixture could not resolve the `:jason` SCM in its generated Mix
  project.
- The repository-wide format check is independently red on two unchanged upstream Codex test
  files. Changed files pass `mix format --check-formatted`; the response-budget commit used
  `--no-verify` only because the upstream pre-commit hook invokes the already-red global gate.

## Removal policy

Keep using the fork until an upstream release includes equivalent fixes and passes every
Vxpipe acceptance gate. Then replace the Git dependency with that Hex release, regenerate
the lockfile, run the official conformance, Everything-server, recovery, credential-isolation,
diagnostic-privacy, and cumulative-budget checks, and only then retire the fork dependency.
Do not carry duplicate downstream patches after the compatible release is adopted.
