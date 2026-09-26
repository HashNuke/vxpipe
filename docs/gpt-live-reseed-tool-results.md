# GPT-Live tool results after a reconnect

## Decision

When GPT-Live loses a socket, host tool invocations already started by the
room continue under their room deadlines. The adapter retains each pending
call reference and tool name while it opens the single replacement session.
A result for one of those references is added to the replacement with
`session.thinking.append` after the replacement acknowledges readiness. A
result that arrives after readiness is appended immediately. The adapter
accepts each result once and splits its JSON into bounded context commands.

The result is private context. It is never sent as a function call output to
the replacement's unrelated Responses delegation and is never added to the
room-published spoken transcript ring used for startup seeding. Failed or
incomplete delegations have already retired their calls and stay stale.

## Alternatives considered

- Replaying the old `response.item.create` on the replacement would refer to
  a call ID from a delegation that no longer exists there.
- Discarding the result would lose work the room has already completed and
  violate the Package 8 continuity contract.
- Adding a tool result to the published transcript ring would present private
  tool data as speech the caller heard.

## Implications and verification

The room still owns invocation deadlines and tool completion events. The
adapter owns only the private context handoff. Context is queued until the
replacement is ready so no command is sent before `session.started`. A send
failure fails the session explicitly; a second loss still fails reseeding.

A fake-socket capability test failed with `:stale_request` before this change,
then passed with the result sent to the replacement as thinking context and
the old call reference retired. The fake-socket, delegation and session files
passed 39 tests with zero failures. The umbrella suite passed 2,853 tests
with zero failures and 59 tagged exclusions; format, warnings-as-errors
compile, strict Credo, unused-dependency and Lean checks passed.
