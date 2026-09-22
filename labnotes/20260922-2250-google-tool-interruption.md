# Google tool interruption

Baseline `bdbad13c` adopted the local opted-in Google response owner. The
eight-file STS regression group passed 207 tests and four post-commit root
static gates passed. Root `mix test` stopped before Persistence tests because
the local PostgreSQL SCRAM connection has no password configured; no credential
was read or logged. The milestone acceptance gate remains open.

Independent read-only re-review used the local fake Google transport and
actually reproduced two issues. A tool call during an unfinished caller used
the caller's `input_turn` as its own turn reference; caller end then skipped
pending response admission because that reference was in `tool_turns`. The
focused controller red asserted the tool turn must differ from the caller and
failed with equal references. On the opted-in path, tool calls now ensure the
current bounded wire-response record and use its reference. Existing tool-call
emission/cancellation moved without behavior change to `STSToolCall`, keeping
the session below the strict-Credo size limit. The focused case now admits
credited PCM after caller end and clears the pending queue after tool result.

The second reproduction showed opted-in `interrupted` with an unfinished
caller left `caller.model_interrupted?` false; a later possibly old `IDLE`
could authorize handle renewal. A focused external-mode red failed on the
missing ambiguity latch. The response delivery path now marks the caller's
model interruption even when there is no active response wire. External and
provider-mode controller cases reject renewal from that stale boundary.

The complete Google controller file passes 58 tests; the eight-file local STS
group passes 210 tests, zero failures. Independent read-only re-review ran the
three new focused cases (3/0), found no new reproducible regression and checked
the session at 759 lines against the 800-line limit. No hosted calls.
Post-commit root static checks and full umbrella acceptance are still pending.
