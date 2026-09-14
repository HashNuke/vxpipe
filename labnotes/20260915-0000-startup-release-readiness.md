# Startup release readiness

## Reproduced gap and decision

Startup retained only a successful readiness boolean while opening playback continued. Its
collector had stopped, so an earlier observation could admit conversation after the required
connection became unavailable. The focused regression deferred caller-media readiness after the
first observation, completed the opening, and expected another readiness request with input still
closed. It failed because the old implementation admitted conversation immediately
(`vxpipe-startup-release-red.log`).

Keep the collected graph and verify every resource through its existing readiness adapter after
opening completion and acknowledged wait pause/clear. Validate the captured inventory and policy
before and after these asynchronous checks; RoomAuthority compares its current binding and the
candidate again before release. Pending or changed resources trigger fresh preparation under the
original deadline. They resume the same paused wait player and cursor. A known failed required
resource or elapsed deadline fails startup. Unaffected processes remain installed.

The release check uses the existing task supervisor and resource adapter dispatch, not a new
coordinator or persistent observer. Individual release probes are bounded to 100 ms; a slow probe
returns to ordinary supervised preparation while waiting resumes. All work remains under the
original startup deadline. Clearing precedes the fresh observation so queued-output cleanup cannot
hold an already successful proof. Disconnect also cancels the exact release task and its graph.
No initial transfer cue, provider restart, extra policy revision or public configuration is added.

## Focused evidence and detours

- The first green attempt consumed the ready notification explicitly and again in the existing
  assertion helper. Removed the duplicate receive and added a no-duplicate assertion; the actual
  readiness-loss behavior was already working (`vxpipe-startup-release-green.log`).
- Added media-generation and policy-revision cases during opening playback. All three require a
  fresh ready connection before admission, then compare participant, room and connection bindings
  to confirm retained healthy instances. The fixture can renew its own readiness generation.
- Extended the existing PCM cursor check through final release. With either model setup pending
  or readiness lost during the notice, the caller receives segments 100, 200, opening, then 300
  from the same player episode. Recovery opens once and emits no further wait frames. The media
  case needed a bounded one-second receive because the release probe itself may take 100 ms;
  its earlier default 100 ms assertion raced that deliberate bound.
- One existing opening-failure test depended on a connection forwarding its room monitor while
  the connection could concurrently terminate during STT attachment. Monitor RoomAuthority from
  the test before injecting failure, as the other startup-failure tests do. Production behavior
  was unchanged by that fixture correction.
- After formatting and the final release-order refactor, 35 focused opening/lifecycle tests pass
  (`vxpipe-startup-release-focused.log`).

## Remaining scope

This checkpoint covers freshness at initial conversation release. Initial setup blocker/timing
observations, complete default/URL/nil and independent resource acceptance, deterministic phone
failure/clocks and full slice acceptance remain open. The other agent's documentation-site and
visual-labnote edits are outside this checkpoint. No browser UI changes or server restart.

## Final checkpoint verification

- Native startup/transfer plus RTVI regression files pass 29 tests, zero failures
  (`vxpipe-startup-release-native.log`). They exercise real peer negotiation, decoded wait/opening
  audio, held RTVI readiness, transfers and terminal signalling with controlled providers.
- All five root gates pass: format check, compilation with warnings as errors, strict Credo,
  `mix test --max-cases 4`, and unused-dependency check. There are 1,326 tests, zero failures and
  15 integration exclusions (seed 333264). Per-app totals: MCP 37, agent runtime 91, engine 614,
  Calls 81, Gateway 342, artifacts 19, persistence 49, Console 93.
  Evidence uses `vxpipe-startup-release-gates-*` logs and results JSON.
- Close the initial microphone/model/first-message release task. The milestone now has 25 open
  checkpoint tasks plus two final-audit tasks (27 total); 14 additional unchecked acceptance/summary
  boxes overlap those tasks. No whole delivery slice is marked accepted by this checkpoint.
- Remaining configuration coverage should include the fast-start path where no wait player was
  needed initially but a later release check returns pending. The current cursor-resume evidence
  specifically starts with an already playing caller wait.
