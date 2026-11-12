# MCP version negotiation

## Diagnosis

- The user successfully completed OAuth in Codex CLI 0.167.2 from the main
  checkout, then native MCP startup failed with JSON-RPC -32600 Unsupported
  protocol version. Python discovery worked when explicitly offering 2025-11-25.
- Confirmed the installed CLI version and project server URL. No environment
  files were read and no credentials or authorization codes were printed.
- A local HTTP peer captured native Codex initialization through the app-server
  inventory API, without starting an agent thread or model turn: it offers
  2025-06-18 with no version header, then uses that version on initialized and
  tools/list requests. The modern-protocol feature is disabled in this setup.
- The authenticated native inventory against Vitrum reproduces the error with
  OAuth status present and zero tools. The probe passes the existing project URL
  as a temporary CLI override because the standalone inventory API initially
  omitted project configuration. It uses Codex's existing credential handling.
- Vxpipe's Protocol module rejected every revision other than 2025-11-25 before
  ExMCP. Handler also forced that revision into the initialization result. The
  installed ExMCP dependency already owns negotiation and session-version checks.

## Decision and implementation

The user explicitly requested spec-compliant acceptance through ExMCP rather
than another Vxpipe validation layer. Remove the version gate, metadata-version
rejection, DELETE gate and hardcoded initialization response. Keep application
request limits, the exposed method set, authentication and tool authorization.
The configured initialize-based transport remains in place; this is not a new
transport implementation or a per-client workaround.

[MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#version-negotiation)
requires echoing a supported offer or responding with another supported revision.
ExMCP already implements this and validates subsequent session headers. The
handler now supplies only server identity and capabilities. Tests that need a
default use the dependency's public version API rather than a product constant.

## Verification

- Red: two focused endpoint integration cases fail with 400 at the project gate:
  the actual Codex offer and an unknown offer requiring the library's response.
  An initial edit command used a wrong relative path and ran the unchanged test;
  corrected the path and obtained the two expected failures before implementation.
- Green: all 22 cases across endpoint, request-lifecycle and sensitive-failure
  files pass. They exercise negotiation through our mounted handler, discovery,
  mismatch rejection, authenticated DELETE and existing resource/privacy bounds.
  No duplicate dependency-level version parser or library unit tests were added.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. No full suite was run. No frontend change required another browser
  or asset build for this checkpoint.
- Deployed the rebuilt QA release. Health returns ok and both system services are
  active; the container retains its 1 GiB limit. Image:
  `sha256:053eb3129ee364684fbc21cf927433b42e781905eecaf0bb94d8d0f85850828a`.
- Repeated the exact native Codex inventory request against Vitrum using the
  installed 0.167.2 binary and existing OAuth credentials: all 17 tools are now
  discovered, server tools capability is present, and discovery reports no error.
  This uses Codex's native MCP client, not the Python MCP implementation used in
  the user's workaround. Python only drives the app-server JSON-RPC diagnostic;
  no agent conversation or model turn is created and no mutating tool is called.
- The earlier direct native check returned OAuth status, zero tools and the
  Unsupported protocol version error; the same check after deployment returns
  the catalog. No re-login, client-version override or project-config edit was
  needed. Diagnostic app-server/local HTTP processes were terminated afterward.
