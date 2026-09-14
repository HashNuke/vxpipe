# Independent opening audio

## Boundary and reproduced defect

The previous checkpoint admitted caller output during initial model preparation, but opening
preparation was still serialized after model construction. It also paused waiting before file
loading or synthesized PCM was available. This checkpoint keeps opening work independent and
switches the caller output only once an opening frame can play.

- Native file regression initially failed waiting for the controlled opening fetch while model
  construction was blocked (`vxpipe-opening-file-red.log`). The caller was already receiving RTP.
- The fixture initially supplied opening settings as call options; RoomSupervisor owns these as
  application configuration and replaces that option. Corrected the fixture to use the established
  application setting, restored by the existing test setup. No runtime configuration API change.
- Native file regression now passes (`vxpipe-opening-file-green.log`): decoded 250 Hz wait audio,
  then 1400 Hz notice, then resumed 250 Hz waiting, all before releasing model construction.
  RTVI rejects caller input after the notice while resources remain unready, and emits bot-ready
  after independent conversational TTS readiness.
- A room-supervised opening output gate holds the first PCM request with ordinary bounded sink
  backpressure, signals playable readiness, and forwards only after the wait player acknowledges
  pause and the actual output clears. It forwards actual correlated playback acknowledgements;
  no duration timer substitutes for completion. File, cached and streamed text can use this same
  boundary without buffering an entire synthesized notice.

## Independent voice and existing contracts

- Native text regression was red waiting for its own opening voice while the model was blocked
  (`vxpipe-opening-text-red.log`). Opening TTS construction now has its own supervised startup
  task and result; installing the main agent configuration never replaces an already completed
  opening. The native text case passes the same decoded wait/notice/wait sequence, then observes
  opening TTS termination before releasing model construction (`vxpipe-opening-text-green.log`).
- The cursor acceptance uses three distinct PCM segments. It acknowledges two wait segments,
  makes the opening playable, observes no overlap, completes opening playout, and receives the
  third wait segment with the original episode ID. Model construction is still blocked.
- Existing opening tests exposed old ordering assumptions: greeting tests now identify voices by
  their configured model instead of creation order; the STT input-isolation test explicitly waits
  for its installed configuration before retaining an attachment. Early attachment is separately
  covered by native tests. A failure test monitors RoomAuthority directly because its forwarding
  embedded connection can terminate while concurrently binding startup STT. The failure remains
  startup_unavailable and never emits call-ready.
- All 15 opening-room tests pass after these fixture corrections, covering the new cursor case
  plus existing human receiver, caching, private recording, file/provider failure and greeting
  behavior (`vxpipe-independent-opening-engine.log`).

## Review and verification

The implementation review keeps this change within the approved opening/setup sequence: no new
call-definition fields or UI changes, no full-notice buffering, no capability restarts at opening
completion, and no replacement startup deadline. The new gate belongs to the existing room
capability supervisor. The original wait player owns its cursor throughout suspension.

- Full native handoff/startup file: 23 tests, zero failures, including both new opening cases
  (`vxpipe-independent-opening-native.log`).
- All five root gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test --max-cases 4`, and `mix deps.unlock --check-unused`.
  The umbrella reports 1,311 tests, zero failures and 15 integration exclusions (seed 787372).
  Per-app counts: MCP 37, agent runtime 91, engine 602, Calls 81, Gateway 339, persistence 19,
  ingress 49, Console 93. Evidence: `vxpipe-independent-opening-gates-*.log` and the results JSON.
- The file/text opening priority task is checked off. Full initial startup release/failure/clock
  acceptance, phone parity and the rest of the transfer milestone remain open. No UI inspection
  was needed for these backend changes; native audio evidence proves decoded delivery/order,
  not physical phone loudspeaker behavior.
