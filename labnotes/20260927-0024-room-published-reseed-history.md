# Room-published reseed history

Date: 2026-09-27. Starting revision: `dd8736ea`.

## Finding and decision

- Independent milestone review found that `CallerEvents` and `Output`
  appended text to the provider before `RoomAuthority` accepted the forwarded
  transcript. A queued final caller transcript could be dropped after hold or
  epoch cutover while still entering the replacement seed. An unassociated
  explicit text transcript could also enter provider history without a room
  turn. This violated checkpoint E's room-published-history contract.
- Moved history append behind a room publication acknowledgment. The room
  emits one only after accepting a final caller transcription or played agent
  text; the owning capability alone calls `Session.append_history/2`.
  `docs/gpt-live-room-history.md` records the asynchronous acknowledgment
  choice and its reseed timing limitation.

## Red-green evidence

- Red: focused run of the fake GPT-Live capability and two room identity files
  had five expected failures in 39 tests. The provider already held `Hi` and
  `Hello` before any room acknowledgment, while the room sent no publication
  acknowledgments.
- Green: after the boundary change, 40 focused tests passed with zero
  failures. They cover the capability's empty pre-ack history, accepted caller
  and agent text, and a caller final rejected after hold.
- First green run surfaced an unreachable error branch in `Output` after
  moving provider history append away from settlement. Simplified that
  branch, then reran the focused tests green without the warning.
- Independent review found that a router error or empty recipient set could
  suppress the transcript after room acceptance while the room still sent a
  history acknowledgment. Two focused suppression tests failed as expected.
  `EventPublisher.publish_transcript_with_recipients/4` now reports the actual
  route set; the caller room path requires virtual-agent route approval and
  the agent path requires human delivery. The combined five focused
  files passed 60 tests, and the publisher recipient test passed three.
- An umbrella run exposed three Morse lifecycle tests that assumed immediate
  capability history append. They now supply a room-publication acknowledgment
  before scripted close; the focused duplex file passed 16 tests. Umbrella
  runs were interrupted after these findings so later tests would not run
  against an obsolete working tree.
- A later independent review found that routed rooms represent the agent as
  a virtual capability, not a connection. Requiring it in the physical
  connection recipient set suppressed every caller history acknowledgment in
  normal routed rooms. A routed-room test failed as expected. The caller
  publication now adds the virtual agent as a route candidate so the router
  can approve that route without attempting network delivery to it; the
  focused room files then passed 29 tests.

## Root verification and open contract point

- The final root run passed format, warnings-as-errors compile, strict Credo,
  unused-dependency check, and `bin/verify-lean`. The umbrella suite passed
  2,864 tests, zero failures and 61 tagged exclusions. The opt-in hosted file
  loaded with the run flag unset: two tests skipped and zero failures. No
  hosted session was started.
- The room sends publication acknowledgments asynchronously. A close can
  snapshot provider history before a just-published acknowledgment reaches
  it. The independent reviewer identified this as a possible completeness
  gap against the milestone's E wording. The milestone now leaves that task
  and E's exit open pending an explicit decision on the snapshot guarantee.
