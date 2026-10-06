# Protected agent openings and phone PCM

## Approved contract

The user clarified on 2026-10-06 that an opening can carry a regulatory notice
and must play completely. This applies to fixed and generated first messages.
Caller onset and an immediate caller text request cannot interrupt an opening.
Generation completion is insufficient: protection ends only when the opening's
matching local output has finished playback. Foreign and stale completion events
cannot release it. Existing media policy, transfer, unavailable-agent and teardown
rules still govern the call's lifetime.

Text agents continue collecting and publishing caller transcription. The room
holds at most 16 completed caller commands while the opening is pending or playing;
a full queue returns the existing busy error. The room submits accepted commands in
order after opening playback. The coordinator still owns normal request scheduling.
Before submission, the room checks that each command's connection, participant,
held state and active turn still match; retired work cannot cross into a new agent.
Queued response deadlines begin at submission so a long greeting does not consume
the internal model's response budget. Ordinary conversation retains interruption.

STS agents discard caller PCM and external start/end controls during the opening.
Discarded valid ingress is acknowledged to release delivery credit and advance the
frame sequence. Identity, epoch, format and policy checks still happen first.
Caller input is not buffered or replayed. Continuous providers receive newly
created, equal-duration silence instead of the caller's PCM so their input clock
keeps running; turn-based providers receive no PCM during the opening. OpenAI's
[greeting instructions](https://developers.openai.com/api/docs/guides/live-conversations)
explicitly require continuous input, including silence, while an opening is generated. The capability tracks opening output identity and
clears its gate after generation, playback and transcript settlement. The room
separately completes its first-message lifecycle from current capability evidence.

## Audio boundary

Provider descriptors continue describing the actual provider PCM. GPT-Live uses
24 kHz mono PCM by default; see the official [WebSocket voice guide](https://developers.openai.com/api/docs/guides/voice-websockets).
Changing a sample-rate label does not convert that audio. Call Engine normalizes
STS output samples to mono linear16 little-endian 48 kHz before submitting frames
to room output sinks, including telephone and WebRTC sinks. This applies to every
STS provider, including Google and local Morse. Provider validation, delivery
credit, output recognition and usage retain the original PCM and duration.

`CallEngine.Media.PCMResampler` performs integer linear interpolation. Absolute
source sample positions keep chunks tiled without timestamp drift; the last
sample in a chunk is held during its final interpolation step. Output conversion
counts source samples separately for each admitted turn. Gateway uses the same
utility to normalize telephone input to the selected speech provider's rate;
Telnyx Opus decodes directly when Opus supports that rate.

## Alternatives and implications

- A provider-specific interruption override would leave text agents and other STS
  providers exposed. The capability and room own the opening playback contract.
- Clearing protection when generation ends would allow an opening buffered in
  the telephone sink to be truncated.
- Buffering STS caller audio would replay stale timing and could change a
  provider-controlled conversation. The user explicitly approved dropping it.
- Letting a text coordinator queue alone serialize openings would wait for model
  generation, not physical playback. The room therefore owns deferred dispatch.
- Putting output conversion in Gateway would leave other sinks dependent on
  provider rates, and sharing a Gateway utility from Call Engine would reverse
  the umbrella dependency direction.

## Verification

Focused fixed/generated overlap tests were written failing before the changes.
Additional failing tests established the 24-to-48 kHz output mismatch, external
activity leak and missing room completion. The affected Google/room/opening group
passed 191 tests. The final default umbrella passed 3,220 tests with zero failures
and 105 exclusions (seed 113691); all five root gates and Lean verification passed.
The clean real carrier test passed, both direct hosted checks passed, and all three
runner shell suites passed. Full evidence is recorded in the
[continuation labnote](../labnotes/20261006-1547-protect-phone-openings.md) and
[GPT-Live milestone](milestones/gpt-live-speech-to-speech.md#hosted-phone-check-first-carrier-run-2026-10-06).
This change does not claim the remaining phone interruption, tool, hold/reseed or
speakerphone echo gates of that milestone have passed.
