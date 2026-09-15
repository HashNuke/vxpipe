# Changing transfer listeners

Continue after local phone acceptance in `7dddbb1`. Nine checkpoint tasks remain:
six changing/multiple-listener tasks, one external carrier-audio check and two
final audit tasks. The prior goal turn made progress by committing phone acceptance.

## Boundary review

The player already provides independent participant cursors, bounded one-frame
output, finite cue drain and multiple sinks fixed at startup. The handoff captures
the audience at authorization and refreshes the prepared graph when inventory
changes. Its refresh starts players only for newly added connections; it does not
update an existing participant's sinks or retire removed connections. A second
connection can therefore acquire a second cursor. A player treats any output loss
as fatal, including an output belonging to a departing listener. These are source
findings until a running-call regression demonstrates their effects.

Start with a native five-participant call: one AI and four existing listeners,
including a receive-only monitor. A human other than the entry caller requests
support, then adds a second receive-only sink while receiving STT is delayed.
Require one retained wait player per participant, both sinks sharing that cursor,
unchanged room/connection resources and deadline, and cue-ordered conversation
after release. Reuse the established private preparation and media gates.

No new UI or provider dependency is planned. Connection removal/replacement,
pre-acceptance membership changes, exact seven/three-second playback positions and
repeated-transfer acceptance remain explicit work; this first case does not prove
the whole slice.

## First regressions and changes

- The first native run reached private support preparation but watched progress on
  the entry caller. Progress is sent to the requesting human, which is deliberately
  the observer in this case. Corrected the fixture to observe that peer.
- The corrected run failed earlier than the cursor assertion: the extra native
  offer returned HTTP 503. Human handoff admission rejected every non-destination
  connection, even an existing participant. Permit existing non-destination
  participants to use the ordinary admission checks; retain private destination
  admission and its exact-attempt controls.
- The owning player regression failed because no sink reconciliation API existed.
  The implementation now fences reconciliation by attempt and generation, keeps
  the cursor, updates only sink monitors and pending acknowledgements, and starts
  added sinks at the next frame. Removed sink acknowledgements cannot advance the
  retained output. All seven player checks pass.
- Track handoff wait players by participant so graph refresh can reconcile the
  existing player instead of starting another cursor. Cue completion continues
  waiting for every actual output. Native and focused engine verification are
  running; no changing-listener checkbox is complete yet.

Evidence logs in the local temporary directory: `vxpipe-changing-listeners-first.log`,
`vxpipe-changing-listeners-red.log`, `vxpipe-changing-player-red.log`, and
`vxpipe-changing-player-green.log`. The large existing native test module takes
roughly 100 seconds per filtered run on this host; the actual new flow runs after
that module compilation. No dev server restart was needed.

## Native monitor admission and regression evidence

The next native run passed admission but failed preparation because the fixture
gave an ordinary human role a receive-only SDP offer. Inventory still demands that
role's microphone; SDP direction does not change server authorization. Use the
existing monitor admission role for the output-only human, including its second
connection, and let a different ordinary human request the transfer. This is the
established receive-only contract, not a new per-connection permission scheme.
Per-connection input selection for an otherwise microphone-enabled participant is
not established by this fixture.

The resulting native flow passes (`vxpipe-changing-listeners-third.log`): four
existing listeners receive URL waiting, support STT holds release, a monitor adds
a second native connection with no input track, all participant players/room
bindings/deadline remain, and every listener receives cue before conversation.
The 46-test owning engine group and strict Credo also pass. The same native case
is now extended to the shared ten-second asset and independently paused exact
seven/three-second positions before sink addition. Full checkpoint/root acceptance
is still pending.

The work has not yet verified arbitrary joins before acceptance, input gating of
new microphone-enabled connections, removal/replacement during cue, or repeated
transfers across changing audiences. Keep those requirements open when curating
the milestone; passing the monitor addition flow does not close them.

## Exact cursors and admission hold

The ten-second native fixture passed with exact byte offsets 672,000 and 288,000
(seven and three seconds of mono 48 kHz linear16). A one-shot debug observer calls
the existing pause API at a chosen acknowledged frame; actual native output still
drains that frame. Neither cursor moves when the second connection attaches, and
both resume into the original players before cue-ordered conversation. Evidence:
`vxpipe-changing-listeners-cursors.log`, one test, zero failures.

A follow-up freezes only the handoff worker during connection establishment. It
reproduces an unheld new connection (`handoff_gate == nil`), so waiting for periodic
graph reconciliation is insufficient. RoomAuthority now sends a monitor-fenced
pending-hold notification as part of ordinary attachment and holds new participant
input at the engine boundary. Both web and phone owners close input and hold the
new output before processing transport events. The worker replaces that initial
hold with the same attempt's actual scope/generation after reconciliation. It
does not restart a provider or grant microphone permission. The native check also
requires the output arbiter to confirm the initial hold while the worker is paused.
Evidence: `vxpipe-changing-admission-red.log`; corrected verification is running.

The corrected native run passes (`vxpipe-changing-admission-green.log`, one test,
zero failures), including initial connection/output hold while the worker is
suspended, exact seven/three-second positions, retained players and the completed
five-participant conversation. The owning engine group passes 46 tests again,
including the added stale-generation assertion. All five root gates are now
running; the existing server process was left alone.

## Root result and checkpoint boundary

All five root checks passed: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The umbrella reports 1,425 tests, zero failures and 16 integration exclusions;
CallEngine contributes 643 tests and Gateway 410. Root logs use the
`vxpipe-changing-listeners-` prefix, with `vxpipe-changing-listeners-results.json`
as the local temporary results manifest. Gateway took 330.5 seconds in this run.

Commit this runnable five-participant addition/cursor checkpoint with its tests,
native guide and milestone/index evidence. Nine compound tasks remain: the six
changing-listener tasks still contain pre-acceptance audience changes, actual
connection removal/replacement, re-entry and repeated-transfer requirements.
The separate live carrier check and two final audit tasks also remain open.
Next, exercise actual sink removal/reconnection while another connection for the
same participant remains; do not infer that from the player-only replacement check.
