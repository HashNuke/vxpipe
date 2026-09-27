# GPT-Live independent review

Date: 2026-09-26. Starting revision: `68fa5a56` plus the uncommitted Package 8
transfer checkpoint.

## Scope and method

- Requested a read-only review through `bin/teammate` from the `vxpag` tmux
  session. The task covers the GPT-Live milestone and completion plan, local
  A-E contracts, F setup/load evidence, lifecycle/fencing, credential privacy,
  dependency direction, and plan drift. It explicitly excludes running tests
  or modifying files, and distinguishes the pending billable hosted check.
- The read-only review returned seven findings. Independent subagent review
  confirmed F1: compiled provider-originated transfer tests cover Morse, but
  the fake GPT-Live socket has only isolated hold/release/teardown coverage.
  The accepted test seam is private fake-wire injection into a compiled
  OpenAI room before caller attachment; public provider settings stay closed.
- Independent subagent review rejected F2, F5 and F6 as current-path defects:
  mute transfer hold preserves pending calls and settlement uses the held
  agent connection; RoomAuthority's transfer Authorizer requires the current
  capability pid and activation; committed teardown stops the current STS
  session without waiting for a provider reply. F3 is an index-staging issue,
  F4 is stale plan prose, and F7 requires separate commits. The plan prose was
  corrected; the staged index and commit scope will be reconciled before
  commit.
- Per the teammate workflow, a second `bin/teammate` command in `vxpag` is
  added the F1 fake-socket mirror tests with red-green evidence. The test
  needed a captured observer outside `:sys.replace_state`, framed caller
  audio to establish a response context, and fake mute/unmute acknowledgments
  during the transfer. Six transfer tests and the related 41-test matrix pass.
  Independent subagent verification confirmed the route and found a missing
  assertion: failed transfer must emit `response.item.create` and
  `response.create` on the fake GPT-Live socket. The success test should also
  confirm the room survives source teardown. A third `bin/teammate` command
  in the same `vxpag` session is adding those assertions; the review loop
  remains open until they pass and are checked again.
- The third command made the assertions pass, but review found
  `Process.alive?/1` checks forbidden by AGENTS.md and brittle exact exit
  reasons. Two further `bin/teammate` commands in `vxpag` removed those checks
  and kept monitored PID termination plus `_ = :sys.get_state(authority)` as
  the room acknowledgement. Both independent subagents reviewed the final
  six-test file and reported no concrete remaining issue. The final root
  static gates and Lean verification pass. After separate test-only timing
  fixes, the umbrella suite passed 2,859 tests with zero failures and 59
  tagged exclusions. Package 8's review gap is closed; checkpoint F still
  requires a review of the opt-in hosted harness and authorized phone evidence.
