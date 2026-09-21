# Speech-to-speech planning — 2026-09-21

## Scope and findings

- Research and milestone planning only. No provider network call, paid load
  test, database write, implementation, or commit was performed.
- The official model catalog names `gemini-3.8-live`. Its native audio mode
  supports output audio transcription, but the Live API does not guarantee
  transcript/audio ordering. Input transcription is also separate from audio
  activity. The room therefore needs a correlation and playback fence.
- The Live API documents approximately ten-minute connection lifetime,
  `goAway`, session resumption updates, interruption, tool cancellation,
  and 16 kHz PCM input/24 kHz PCM output. A resumed connection must retain
  the same conversation; a fresh one cannot be silently substituted.
- Current Call Spec compiler requires `model_inference` for every agent, and
  only admits human STT plus agent LLM/TTS. `RoomAuthority.InputTurns` publishes
  human transcripts through `EventPublisher.publish_transcript`, while
  `AgentOutput` owns text/TTS playback events. The STS path needs an agent-owned
  capability and explicit agent-output STT role, not a reuse of human STT.
- Provider manifests currently declare STT/TTS, not STS. Console has an `s2s`
  type/label in setup code, but Google does not advertise it in the catalog.
  The milestone gates that badge on a working hosted adapter.

## Decision and barriers

- Chose one scoped STS capability under the room's capability supervisor.
  RoomAuthority retains source/policy attribution and all public transcript
  publication. The transcript source is selected before admission: provider
  output text or a separate agent-output STT. No runtime fallback.
- Chose Morse STS as the first runnable proof, then transcript-less Morse,
  then Google. This orders permission, playback, interruption, and lifecycle
  tests ahead of the billable provider adapter.
- Local review found that human STT currently dispatches its final text into
  the text-model response path. The STS plan keeps that transcript but prevents
  a duplicate response, and names agent-output recognition separately as
  `output_speech_to_text` to avoid inheriting human STT defaults.
- Google Live's documented interruption signal does not by itself establish
  that speech onset is prompt enough for this room's barge-in target. The plan
  requires measured onset evidence or an explicit human STT/local activity
  source before enabling the mode.
- Hosted interoperability remains a future opt-in gate because it can incur
  charges. The milestone explicitly leaves the Google badge gated until that
  gate passes. No credentials were inspected or logged.
- This task produced `docs/milestones/agent-speech-to-speech.md` and an index
  entry. Implementation checkboxes remain open.

## Verification

- Reviewed current source/contracts and official Google model, Live API,
  session, tooling, and cost documentation on 2026-09-21.
- Local Markdown links in the new milestone and updated index resolve.
  `git diff --check` passed; the index and milestone leave implementation
  unchecked. No code tests are relevant to these edits.

## Full-scope verification cadence — 2026-09-22

- The requested scope is the complete A–F STS milestone, including Morse,
  agent-output STT, Google Live, tools, transfers, Console and documentation.
  None of the implementation or acceptance boxes has been completed yet.
- During implementation, use the smallest failing behavior test and focused
  child tests for each slice. Defer repeated umbrella suites, integrated
  manual calls, rendered UI inspection, synthetic load and independent
  implementation review until all A–F implementation work is in place.
- Run one coordinated final acceptance pass, fixing findings and rerunning
  affected checks. A focused test that proves new instability is investigated
  immediately. Google remains unadvertised until a separately authorized
  billable hosted check passes; no such check was run for this planning edit.
