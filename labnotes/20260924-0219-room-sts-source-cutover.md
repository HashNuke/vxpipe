# Room STS source cutover

Scope: complete the WebRTC room-coordinated hold/reopen slice on top of the
existing receiver-owned `Connection` barriers. Telephony raw callback/Leg source
fencing remains its separate milestone task. The bounded ten-call check will
use the existing local measured load lane; it is not evidence for the WebRTC
source barriers themselves.

## Design/dependency review (before new tests/runtime)

`RoomAuthority` is the lifecycle coordinator and must remain responsive while
waiting for a monitored Gateway `Connection`. It sends correlated asynchronous
requests from its own PID, with one room token, the exact attachment monitor and
an absolute deadline. The room closes both STS and selected native STT ingress
first. It waits for the exact source-hold receipt before retiring the selected
STT allocation. A replacement recognizer must report a fresh, ready allocation
generation and matching source intervals; the room binds that origin to the
closed ingress and a new STS input epoch before asking Connection to arm. Only
the exact arm acknowledgement permits reopening currently authorized input.

The existing Connection checks the room caller, attachment, token and bounded
deadline, and its two receiver-owned barriers fix source epochs before media is
forwarded. A missing or ambiguous acknowledgement never opens room ingress.
The existing transfer-held participant state is a separate hold: selected STT
readiness cannot clear it. Where STS is retired or its route is denied, selected
human STT may resume only after the source cutover has completed and only under
its own current room policy; this does not authorize STS input or activity.

This sequence follows the reviewed contract in `labnotes/20260923-0243-sts-activity-provenance.md`.
The source protocol applies only to WebRTC in this checkpoint. No transport
receipt-time, remote capture, ICE/DTLS buffering or telephony drain claim is
included. The discovery-first task breakdown and verification expectations are
recorded under the WebRTC source-cutover item in the milestone before the new
room reds.

## Progress

- [x] Focused red/green: the room hold test first failed because no async
  source request existed. Its green exercises source hold, validates the exact
  receipt, requests arm with the same token/attachment, and reopens only after
  the matching arm response. The STT ingress regression first failed because a
  transcript-origin replacement left admission open; it now closes locally,
  requires a fresh source epoch, binds the fresh provider allocation, and rejects
  mismatched source epochs. Room speech/ingress tests pass 39/0 on seeds 0 and 1.
  Gateway source-receiver/cutover/STS-input tests pass 23/0 on seeds 0 and 1;
  the Call Engine text attachment test passes 4/0 on both seeds; compiled Morse
  STS room tests pass 11/0 on seed 0.
- [x] Call Engine child suite passes 1,505 tests, zero failures, 30 excluded,
  seed 0. The Gateway child suite did not finish within its 240-second bound and
  produced no ExUnit summary; its focused changed-path tests are green, so the
  full Gateway run is not claimed as a pass.
- [x] Root format check, warnings-as-errors compile, strict Credo (1,105 source
  files, no issues), unused-dependency check, and `git diff --check` pass.
  The umbrella `mix test` and independent implementation review remain part of
  the coordinated final pass and are not claimed for this slice.
- [x] The bounded local measured lane passes all three ten-call modes in
  25.4 seconds: 29 completed turns, ten interruptions, nine healthy survivors,
  ten cleaned calls, zero errors. Host: x86-64, four logical CPUs, 7,750 MiB RAM;
  two BEAM schedulers. Full machine-readable `CALL_LOAD_JSON` records are in
  `20260924-0219-room-source-cutover-load.jsonl`. This fixture load exercises
  embedded room calls, not Gateway WebRTC source cutover.
- [x] Commit this vertical slice as `b9075c39`. Continue the remaining room
  acceptance as a separate checkpoint: prove transfer/policy overlap, native
  STT retirement and fresh ready-generation binding through the real
  RoomAuthority lifecycle, transcription-only recovery while STS is retired,
  stale/late evidence and owner/timeout failure cases. Telephony cutover remains
  separate.
