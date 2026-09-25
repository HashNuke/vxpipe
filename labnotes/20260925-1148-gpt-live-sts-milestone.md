# GPT-Live STS milestone

## Task

Specify how the platform would support OpenAI GPT-Live as an agent
speech-to-speech provider, as a separate milestone after the provider-controlled
STS milestone. Documentation only; no runtime changes.

## Sources checked (2026-09-25)

- OpenAI [GPT-Live session guide](https://developers.openai.com/api/docs/guides/live-conversations):
  transcript deltas carry `delta`, `start_ms`, `end_ms` (milliseconds from
  session start); "no item ID or event that marks a completed conversational
  turn"; `session.output_audio.delta` has no timing; close reasons
  `close_requested`, `expired`, `content`, `remote_hangup`, `connection_lost`;
  startup history at most 128 messages / 8,192 tokens; `store: true` needed for
  forking.
- OpenAI [delegation and tools guide](https://developers.openai.com/api/docs/guides/live-delegation):
  Responses vs client delegation; function calls read from nested
  `response.output_item.done` in `response.event` envelopes; every pending call
  needs `response.item.create` before `response.create`; instructions do not
  cancel backend work.
- OpenAI [GPT-Live getting started](https://developers.openai.com/api/docs/guides/live):
  voice billed per second; backend usage billed separately.
- Not found in those pages: the new-session WebSocket URL, WebSocket audio
  format list, session duration limit, and behaviour when the caller talks over
  the model. The milestone's checkpoint A verifies these before implementation.
- Two open-source GPT-Live client implementations (shallow clones, current
  default branches). Both close a caller turn after about 0.8 s of quiet (one
  counts pushed microphone audio, one uses a timer), derive agent speech from
  an energy gate on output audio, align output fragments to audio using the
  fragment timeline, treat interrupt/truncate as no-ops, and reseed a new
  session from history on reconnect.

## Decisions

- One room-facing STS contract; the adapter infers turns and segments output.
  New descriptor facts (`output_shape`, `barge_in`, `continuity`,
  `tool_cancellation?`, `:inferred_gap` endpointing) declare what is inferred.
- Only room change: skip the output fence on caller onset when
  `barge_in: :provider`.
- Agent text alignment maps fragments into admitted-output offsets so the
  existing playback fence works per fragment.
- Revised after the user's review against natural phone-call behaviour:
  - Hold mutes input and discards output locally, keeping the session; the
    model gets hold/release context via `session.thinking.append`. The first
    draft stopped and reseeded, which caused reconnect silence on release, lost
    in-progress backend work and left the agent unaware of the hold.
  - The output energy gate only marks turn boundaries; a 300 ms pre-roll keeps
    quiet word onsets from being clipped.
  - After a reseed, the agent continues if the drop interrupted its reply or an
    unanswered caller turn; otherwise it waits. Renew before a documented
    duration limit at a quiet point.
  - Added carrier echo to the milestone and its hosted check.
- Outbound agent-to-person calls moved to scope boundaries: the platform does
  not place them yet. The greeting rule (wait for the callee to speak) is
  recorded there for later.
- Specification frozen on 2026-09-25 at the user's request. Later changes are
  recorded amendments; checkpoint A's API verification is the expected source.
- Kept after that review: provider-owned barge-in (backchannels do not cut the
  agent off), inferred turns for records only, and overlap not cancelling tools.
- Usage reuses the existing `:milliseconds` unit
  (`usage/measurement.ex`).
- No OpenAI provider package or credential exists yet
  (`docs/existing-provider-credentials.md`); checkpoint D adds one.
- A Morse duplex provider shares the inference modules so the default suite
  covers the room paths without billing.

## Output

- `docs/milestones/gpt-live-speech-to-speech.md`
- Index entry 34 and specification-review row in `docs/milestones/index.md`.

## Verification

Documentation-only. Local links in the new milestone resolve; no references to
the renumbered index entries exist elsewhere in `docs/`.
