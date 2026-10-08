# Live call cleanup

## Scope and decisions

- Add explicit `telephony:hangup`, `telnyx:hangup` and `twilio:hangup` commands to
  `bin/livetests`. Ordinary test-run behavior remains unchanged.
- The initial account-wide request was refined by the user: default cleanup must
  target calls to/from this machine's provisioned numbers; retain `--all-calls`
  for account-wide recovery. Telnyx ownership uses both exact machine tags;
  Twilio uses the exact machine FriendlyName.
- Keep cleanup in a sourced shell file, separate from provisioning and endpoint
  management. Use existing runner credential loading, tested with synthetic files.
- Never read or modify the protected live credential file. No real calls are
  terminated during development. Existing milestone/editor changes and labnotes
  were present at the start and are outside this checkpoint.

## API evidence and rejected alternatives

- Reviewed the official Telnyx OpenAPI specification and carrier docs. Telnyx
  `/connections/{id}/active_calls` is cursor-paginated and returns call-control and
  leg IDs without numbers. `/calls/{id}` does not expose numbers either.
- Rejected application-name scoping: unrelated numbers may share an application,
  and test numbers can dial through a differently named application. Discover
  tagged numbers, enumerate all Call Control applications, then match each live
  leg through documented `call_events` leg/from/to filters. Require an initiated
  event before classifying a leg; fail closed when number evidence is missing.
- Twilio lists queued, ringing and in-progress calls with from/to fields. End
  connected calls with `Status=completed`; cancel the other active states with
  `Status=canceled`. Follow `next_page_uri` within the configured account.
- Collect complete inventories before mutations to avoid skipping shrinking
  pages. Recheck after each of at most three passes; final inventory emptiness
  determines success, including races where paired legs disappear beforehand.
- Bound HTTP requests and omit raw carrier errors, URLs and response bodies from
  reports because they may contain call-control tokens, credentials or numbers.

## Red/green evidence

- New `test/shell/livetests_hangup_test.sh` initially failed because
  `telephony:hangup` did not exist. Added cleanup dispatch and implementation;
  the account-scope and initial machine-scope suite passed.
- Strengthened number-scope fixtures with unrelated calls on the same Telnyx app,
  and the machine's second number on another app. The focused suite failed with
  `default Telnyx cleanup touched other numbers or left this machine active`.
  Added exact number evidence through Telnyx events; the focused suite passed.
- Added a missing-from/to Twilio response case. It failed with
  `unclassified Twilio calls reported success`. Required number fields for scoped
  cleanup, while account cleanup needs only call identity/state.
- Added no-provisioned-number and malformed-tag cases. Each failed for its
  expected reason before its fix. Empty default scope avoids querying unrelated
  calls; malformed Telnyx tags fail instead of matching a string substring.
- A large application-response fixture exposed an OS argv-size boundary: passing
  accumulated JSON with `--argjson` could fail and make resource discovery appear
  empty. The regression ran red with `large application metadata caused a false
  empty inventory`. Resource/call pages now merge through stdin, merge errors
  propagate, and application snapshots retain only required IDs.
- Final verification is recorded below. No speech/cutover state machine changes,
  so Lean is outside the change's verification scope.

## Handle-scoped Elixir teardown

- The user extended the task to teardown every telephony live test in Elixir,
  and confirmed cleanup must use only the call-control IDs/SIDs used in that test.
- Gateway's direct carrier tests already registered hangups but discarded the
  result. Added a shared test-owned handle cleanup helper that queries the exact
  handle, ends it when active, and verifies terminal state. No account lists or
  number discovery are used by Elixir teardown. Eight focused tests ran red
  against the missing helper, then green after implementation.
- Console previously stopped local room authorities. Added test-only adapter
  wrapping to retain returned dial handles and authenticated initiated callback
  handles for fixture numbers, including transfer legs and failed answering.
  Each test registers a separate carrier on_exit callback. The collector belongs
  to the case supervisor because ExUnit stops per-test supervised children before
  on_exit callbacks; it can retain handles independently of rooms and the DB.
- Collector scopes deduplicate handles, attempt all cleanup despite a failure,
  and immediately end handles arriving after a scope closes. Credentials stay in
  memory and diagnostic state/error reporting is redacted. Four collector tests
  ran red against the missing module, then green; callback-number and failed-answer
  coverage was added to the focused group.
- The first umbrella run began before the teardown extension. It found a startup
  attachment shutdown race in the existing CallLifecycleRoomTest (seed 680215),
  and picked up four new collector tests while they were intentionally red. That
  mixed-source run is not final acceptance evidence. A focused rerun of the
  existing failure passed with the same seed. The fresh final umbrella run also
  passed that case; no unrelated runtime repair was made or claimed.

## Final verification

- All four runner shell suites passed: `livetests_test.sh`,
  `livetests_tools_test.sh`, `livetests_telephony_test.sh` and
  `livetests_hangup_test.sh`. The final hangup suite includes the large metadata
  regression and passes after the streaming merge fix.
- Gateway's focused handle cleanup suite: 8 tests, zero failures. Console's
  collector/fixture/peer group: 15 tests, zero failures, 13 live/integration cases
  excluded. Real carrier dialing and hangup were not run.
- All five umbrella gates pass: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test --seed 680215`, and `mix deps.unlock --check-unused`.
- Final umbrella: 3,307 tests, zero failures, 120 excluded. Gateway contributes
  585 passing cases and Console 227. The new Elixir source remained unchanged
  during this final run; the separately verified shell metadata fix affects only
  explicit recovery subcommands.
- `bash -n` passes for the runner, cleanup library and new shell suite.
  `git diff --check` passes. Existing editor/milestone work and earlier labnotes
  remain outside this checkpoint. The user subsequently requested a commit of
  the cleanup checkpoint.

## References

- [Telnyx OpenAPI](https://github.com/team-telnyx/openapi/blob/master/openapi/spec3.json)
- [Telnyx active calls](https://developers.telnyx.com/api-reference/call-information/list-all-active-calls-for-given-connection)
- [Telnyx events](https://developers.telnyx.com/api-reference/debugging/list-call-events)
- [Telnyx hangup](https://developers.telnyx.com/api-reference/call-commands/hangup-call)
- [Twilio Call resource](https://www.twilio.com/docs/voice/api/call-resource)
