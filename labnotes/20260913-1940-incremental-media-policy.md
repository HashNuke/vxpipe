# Incremental media policy

## Request and decision

The user requested a diff of affected services when media policy changes, rather
than restarting every service on a room revision. Joining the unrestricted human
support destination changes membership but does not change the caller's existing
transcript, audio, or recording rules. Keep those resources and their queued work.

The room still has one monotonic admission revision. Each source/recipient path
also keeps the last revision that changed its relevant permissions. This avoids
relabeling buffered data as newly permitted content, while preventing unrelated
revisions from invalidating healthy streams. See
[the decision](../docs/incremental-media-policy.md) for scopes and alternatives.

## Speech checkpoint

- Observed the new STT preservation regression fail because membership closed the
  provider connection. After implementation it preserves the transport, provider
  sequence, and source permission interval through membership/audio-only changes.
- Observed the transcript router regression fail with `unknown_policy_revision`
  after unrelated revisions evicted the active speech interval. Active intervals
  now remain available in addition to bounded historical snapshots.
- The STT ingress compares the same source interval and preserves queued/in-flight
  bookkeeping when unchanged. Real transcript changes still purge old input.
- Existing provider replacement regressions now change actual route/storage
  permissions. They still cover stopping denied demand, restarting restored demand,
  stale callbacks, cancellation of superseded reconnects, and failure handling.
- Focused engine policy/STT/ingress/router/mixer checks passed: 52 tests, zero
  failures. Audio integration is committed separately using the shared interval
  contract; this checkpoint preserves compatibility with existing audio handling.

The combined speech/audio candidate passes all root completion gates under
`MIX_ENV=test`: formatting, warnings-as-errors compilation, strict Credo, the
umbrella suite (1,006 tests, zero failures, 15 integration cases excluded), and
unused dependency checking. These checks were run on the combined worktree before
splitting the two compatible commits by purpose.

## Review

The room authority remains the sole policy owner. Global revisions still enforce
ordered, bounded admission acknowledgements; scoped intervals only decide which
resources/data are invalidated. History retains active speech intervals plus a
bounded recent window. Restriction followed by relaxation creates new intervals,
so old content cannot acquire newly restored permissions. Current membership still
controls recipients. No per-packet database work or new dependencies are introduced.

No launcher or UI changes. The user's development server stays running; live checks
use a separate localhost diagnostic VM. No packaging or retention work is included.
