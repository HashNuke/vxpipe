# Incremental audio policy

This checkpoint applies the shared
[permission interval contract](../docs/incremental-media-policy.md) to Gateway
normalization/output and the engine mixer/recording queues.

## Implementation and regression evidence

- Gateway ingress and egress preservation regressions first failed with
  `unavailable`: unchanged revisions waited for replacement pipeline readiness.
  Unchanged paths now acknowledge immediately, retaining codec state, RTP clock
  alignment, playback, and in-flight acknowledgement bookkeeping.
- The mixer preservation regression first failed because unrelated membership and
  transcript revisions erased queued live audio. Input frames, recipient output,
  and recording buffers now survive unchanged permissions. Actual changes purge
  the affected intervals, and absent sources are removed from pending queues.
- Recording uses its own interval. Changing storage permission leaves an unchanged
  monitor output interval intact; restoring recording cannot replay denied data.
- Focused engine checks passed 52 tests; Gateway ingress/egress passed 12. Existing
  human-only and recording fixtures now obtain the appropriate source/output
  intervals rather than assuming the newest admission revision applies everywhere.
- The first full suite caught a real two-peer fixture timeout: it advanced caller
  RTP by 20 ms across a private briefing lasting over one second. Previously the
  unnecessary normalizer restart masked that stale timestamp. The fixture now
  advances RTP with elapsed time, matching a continuing stream. The focused
  bidirectional private-acceptance test passes, including the original private
  isolation assertions.

## Live verification

Used a separate localhost Phoenix VM with the configured Gemini/Deepgram providers
and headless Chrome fake microphones; the user's development server was untouched.
A caller requested human support, a second browser tab connected to the transfer
desk and accepted, and the desk reached `Main room active`.

At room revision 2 the caller had one STT transport and generation-1 audio ingress
and egress pipelines. At revision 4, after human admission and source-agent removal,
all three retained exactly the same process identities; the speech interval
remained 1. Only the destination's new ingress/egress pipelines were created.
The caller remained connected after acceptance. More than a minute afterward,
both server peers had positive inbound/outbound RTP counts (5,820/1,277 and
4,394/2,005 respectively). Fake audio establishes media flow, not subjective phone
audio quality. The diagnostic browser and VM were stopped after verification.

## Completion and review

All root completion gates pass under `MIX_ENV=test`: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
`mix deps.unlock --check-unused`. The final umbrella run contains 1,006 tests,
zero failures, and 15 excluded integration cases. No dependencies or UI changed.

Reviewed source/recipient permission differences, absence checks, stale callbacks,
recording gates, sequence continuity, queue notifications, and barrier ordering.
The global admission revision still advances and every enforcer acknowledges it;
only resource replacement and data invalidation are scoped to changed permissions.
Historical revision-wide reset descriptions in the milestones are superseded by
this user-approved correction. Packaging and retention remain on hold.
