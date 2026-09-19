# Semantic Morse STT — checkpoint A

## Scope and decisions

The user authorized implementation of the simpler speech integrations milestone,
checkpoint commits, pushnotify updates, and GPT-6 Astra xhigh review. This checkpoint
introduces standalone native Morse STT; room migration remains checkpoint B.

- Reuse Morse Config/Decoder; no new codec, JSON or fabricated provider request ID.
- One supervised session owns a provider and a bounded event channel. The channel
  holds events during startup and stamps producer/generation/sequence identity.
- Only the owner admits input. Exact event acknowledgement precedes consumption;
  one delivered event and 32 queued events bound slow-consumer retention.
- Closing discards decoder carry. Owner loss must kill even a held startup rather
  than relying on a supervisor processing its ordinary mailbox.

## Red/green evidence

- The independent SOS 2 fixture copied from the existing codec test first failed
  because Speech.Event was absent. After the initial implementation, the owning
  child test passed (1 test, 0 failures).
- Added cases for closed configuration, invalid input, envelope validation,
  unacknowledged-event overflow, discard-on-close, owner loss, startup deadlines,
  command deadlines and redaction. These are being driven red/green separately.
- Two initial shell edits used root-relative paths from the child directory and
  failed before modifying files; corrected the working-directory mismatch.

## Review

GPT-6 Astra xhigh preflight found no architecture blocker, with required evidence
for owner loss during held startup and retirement before a timed-out input can
be followed by another. It also identified old transport flush-on-close and
fake local request IDs as behavior to avoid in this new provider.

Final diff review and root acceptance gates remain pending.

## Review corrections and pause

The first full Astra xhigh review reproduced four defects: private-init values retained by
supervisor arguments, raw startup error returns, orphaned trapped providers before bind,
and orphaned blocked providers on command-timeout cleanup. Regression tests first failed for
all four. The prototype now uses an ephemeral private-init handle, normalized startup errors,
bounded OTP startup and forced retirement of the known provider. Seventeen focused contract
tests passed after those corrections. This is not final checkpoint acceptance.

A shared-supervisor startup concern caused the user-requested pause. The subsequent
verification-only task proved it with isolated actual Morse sessions and measured local
latency under load. See `20260919-1624-speech-startup-isolation.md` and
`docs/speech-startup-isolation.md` for the new failing regression, controls and 68,400-turn
latency evidence. The milestone is updated to paused/zero completed checkpoints; no runtime
fix or checkpoint commit occurred in that verification task. Current room paths remain old.

An initial compile check passed before the later review corrections; strict Credo passed
at that stage. Full root acceptance is still pending and must be rerun after the startup
isolation fix. The reviewed prototype and all evidence remain uncommitted.
