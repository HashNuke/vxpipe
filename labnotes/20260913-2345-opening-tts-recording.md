# Opening TTS and recording

## Requested outcome

Text opening audio must explicitly select its own TTS profile, work with a human initial
receiver, and never inherit an agent's voice. Verify and fix the suspected recording leak
during opening playback. Preserve unrelated root sound assets and earlier sound labnotes.

## Recording checkpoint

- Inspected opening input admission, Gateway's parallel STT/room-audio delivery, room mixing
  and the recording subscriber. STT had the opening gate; decoded room audio bypassed it.
- Added a room-level recording regression using the real mixer and recording subscriber with
  an injected writer. First corrected the fixture to use the authoritative per-source policy
  interval; then the intended red failure showed two delivered frames (full mix and individual
  track) before playback completion where zero were expected.
- Initialize the mixer with a closed opening gate when the pinned plan has an announcement.
  Actual opening completion opens that gate before STT/greeting admission. Record the opening
  completion timestamp in the mixer's existing clock domain so late-decoded held frames cannot
  be admitted after the gate opens. The gate also protects the recording-egress path. No media
  policy revision or provider restart is introduced.
- The new regression is green: start/progress/enqueue do not permit recording, delayed audio
  from the held interval remains discarded, and subsequent caller audio reaches both recording
  streams. Existing focused opening/mixer/recording coverage: 26 tests, zero failures.
- Root gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test` (1,008 tests, zero failures), and
  `mix deps.unlock --check-unused`. No browser/UI changes were made in this checkpoint.
  The independent opening TTS checkpoint remains pending.
