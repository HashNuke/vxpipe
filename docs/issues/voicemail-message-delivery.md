# Leaving voicemail messages

Status: deferred for later review. R32's initial behavior disconnects a destination
when configured provider detection reports an answering machine. This issue records
possible future message delivery, not an approved feature, schema, or runtime change.

## Current boundary

Detection uses the configured provider facility when available; it is not mandatory
on every call and has no local classifier or LLM-based substitute. Preserve observed
classification, provenance, and unknown outcomes without claiming perfect accuracy.
On machine detection, disconnect the attempted outbound destination leg. During a
transfer, retain the original caller/source conversation under normal permissions
and return a typed failure; do not hang up the room. An initial outbound attempt to
its only remote human ends that attempted leg/call without leaving a message.

Unknown, disabled, or unavailable detection is not proof of machine or human.
An unknown transfer still requires explicit recipient acceptance within its existing
30-second total attempt deadline, without resetting or extending the clock. Provider
classification does not substitute for that acceptance.

Agent instructions own ordinary closing wording and when to invoke existing hangup.
This issue does not reintroduce the rejected platform speak-then-end API, mandatory
playback-drain workflow, or a promise that prompts guarantee completed playout.

## Questions to revisit

- Which provider greeting-completion or beep evidence is available, and how should
  missing, uncertain, delayed, or conflicting evidence affect message delivery?
- Should a message be optional, where would its policy live, and what authorized
  fixed or generated message sources should be supported?
- How would playback be confined to the correct destination leg, excluding private
  caller audio, variables, consultation, or other unauthorized information?
- What evidence supports attempted, partially delivered, completed, or unknown
  delivery, and what deadlines and failure outcomes are appropriate?
- Which provider differences require explicit compatibility work rather than an
  assumed universal beep, greeting, or playback-completion signal?
- How should a future delivery operation interact with transfer acceptance and
  existing call limits without silently extending deadlines or committing a
  transfer to an answering machine?

These are future review questions, not selected options or a new shutdown-speech
workflow. No automatic voicemail speech, media fetching, or provider tuning is added.

## Future verification

After approval, use controlled provider evidence and playback outcomes to verify
correct-leg isolation, permission checks, honest delivery status, bounded waiting,
and unchanged source/caller responsibilities. Current verification is documentation
only; no outbound call, message playback, or runtime test was performed.

Related: [call-spec design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), and [gap review](../call-spec-gap-review.md).
