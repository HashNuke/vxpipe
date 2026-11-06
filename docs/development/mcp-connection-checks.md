# Transient MCP connection checks

This checkpoint validates static credentials, initializes a tenant-scoped MCP
client and fetches a bounded tool catalog. It never invokes tools or persists a
connection. Authorization, encrypted record storage, OAuth and the production
modal are separate tasks in [the Integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

## Input and destination boundary

`StaticConfiguration` accepts an HTTPS endpoint and exactly one static method:
none, bearer, custom headers or Basic. Method-specific fields cannot carry stale
credentials from another method. Header validation rejects managed transport
headers, duplicate names and line breaks. Its inspection omits endpoint and secrets.
Runtime/protocol adapters, timeout limits and private-host policy are trusted
server options; request input cannot select them.

The production client profile rejects localhost and IPv4/IPv6 loopback literals,
including when listed as private hosts. ExMCP's full DNS-answer validation and
address pinning remain active for network requests. Private-network exceptions
are operator-owned. A separate internal HTTP-loopback fixture entry supports
local integration tests and cannot be selected by request data.

## Lifetime and logging

The shared supervisor admits at most eight sessions. Each session starts its
lifetime controller, client wrapper and worker without waiting for network I/O.
An absolute ten-second deadline is established before admission. The wrapper
registers its PID with the lifetime controller before receiving configuration or
initializing ExMCP. Owner death or expiry can therefore kill blocked initialization.
Readiness is acknowledged before the worker asks for client status and tool pages.

Supervisor start arguments contain identity and lifetime metadata only. Sensitive
options are handed to the registered client through the lifetime controller.
Both controllers redact OTP status/report fields; the wrapper normalizes delegated
exceptions and returned stop reasons. Fixed public failures do not echo server
responses, options or credentials. These controls cover the check path, not all
other ExMCP consumers.

The checker disables the optional persistent GET stream and reconnects. POST
JSON/SSE responses remain supported by the pinned dependency. This keeps HTTP
work in the supervised client rather than spawning unlinked POST workers for a
persistent stream. Discovery retains existing page, decoded-byte and schema limits.

After discovery, the worker attempts an explicit disconnect with a 250 ms caller
budget, including session DELETE when the server issued a session ID. Cleanup is
best effort: cancellation, unavailable servers or expired deadlines may prevent
remote deletion. Local cleanup forcefully retires the client and observes its
termination before returning a result. The caller allows 100 ms for result delivery
after the deadline, followed by a separate 250 ms supervisor-shutdown call budget.
These are local budgets, not a hard wall-clock result-return guarantee. A successful result is
eligible only when the lifetime controller accepts completion before that deadline;
observing client termination and returning an already accepted result may occur
during the cleanup budget. Completion handled after expiry cannot become success.

## Alternatives and verification

Synchronous ExMCP startup inside the shared supervisor was rejected: one slow
initialization blocked admission and deferred caller-death cleanup. A timer child
alone did not fix a parent still blocked in child startup. A supervised callback
wrapper makes startup immediate, preserves the installed ExMCP protocol handling,
and owns status/error redaction without changing the dependency. This wrapper is
coupled to the pinned client's GenServer callbacks and must be checked on upgrades.
Keeping the optional persistent stream was rejected for these short checks because
the dependency starts unlinked POST workers in that mode.

Focused unit and local HTTP fixtures cover auth exclusivity, policy injection,
loopback rejection, zero-tools versus failure, owner/deadline cancellation during
startup, responsive capacity, concurrent successful checks, late completion,
formatted/structured report redaction and explicit DELETE. Held initialization,
tools-list and DELETE requests prove actual socket closure on cancellation or
bounded cleanup. See [checkpoint evidence](../../labnotes/20261106-2354-review-mcp-checks.md).
