# Wait music during startup and tool work

Status: deferred for later review. This issue covers possible audio while waiting
for required startup readiness (R27) or long-running tool work (R29). No wait-music
option or runtime playback feature is approved yet.

## Current boundary

Required provider/connection readiness has a configurable 30-second startup
deadline. A terminal failure fails early; timeout aborts startup and releases
resources. Deliberate opening-audio playback is a separate gate, not failed
provider readiness or a file to truncate at that deadline.

Long tools do not trigger automatic periodic progress speech. Agent instructions
control kickoff and result speech while ordinary conversation can continue under
the background-tool contract, using the same agent and one coordinated voice.
Waiting music is a possible later presentation choice, not a retry, completion
signal, or business-success announcement.

## Questions to revisit

- Which music sources, configuration scope, supported formats, and caching rules
  should be offered? How are assets obtained safely and reused?
- What exact startup/tool-wait states should begin playback, and should music
  be absent when the agent is already conversing?
- When must music end or pause as readiness, tool results, participant speech,
  agent speech, cancellation, or call termination arrives?
- How should music mix with or yield to speech, and which participants, monitor
  outputs, and recording taps may receive it?
- How does interruption/barge-in interact without treating speech interruption
  as cancellation of the underlying tool?
- How do opening-audio input gating and capability/recording permissions prevent
  unintended music or participant audio from reaching STT or recordings?
- How should unavailable assets or playback failures behave without extending
  startup deadlines, inventing tool outcomes, or holding a call indefinitely?

Do not infer warm transfer/consultation support, automatic repeated announcements,
a new media source option, or a bypass of existing permissions from this issue.

## Future verification

After a design is approved, test startup and tool waiting independently with
controlled readiness/results and distinguishable speech/music tracks. Verify
authorized routing, prompt stop/yield behavior, no forbidden STT/recording input,
and unchanged startup, tool, and whole-call time limits. The current checkpoint
adds documentation only; no audio playback or browser checks were performed.

Related: [call-definition design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), and [gap review](../call-definition-gap-review.md).
