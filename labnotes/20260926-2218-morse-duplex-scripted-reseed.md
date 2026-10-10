# Morse duplex scripted reseed

> Relocated from `docs/morse-duplex-scripted-reseed.md` on 2026-10-09. First recorded source commit: `1baf3af8cf5b` (2026-09-26T22:18:14+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260926-2145-morse-scripted-reseed](20260926-2145-morse-scripted-reseed.md).
> Maintained contracts/progress: [live-provider-tests](../docs/development/live-provider-tests.md), [speech-provider-contract](../docs/speech-provider-contract.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

## Decision

The local Morse duplex provider accepts `scripted_closes?: true` only with
`clock: :manual`. Tests call `DuplexSTSSession.script_close/2` with `:expired`
or `:connection_lost`. The provider resets its session-local decoder, turn
inference, output segmenter, timeline and clock, then resumes only when the
drop interrupted a burst or followed an unanswered caller turn. It returns
the bounded text history that a replacement would seed, so tests can compare
it with transcripts published by the real STS capability.

The provider keeps the capability process, its latest response context, and
any already admitted output until playback settles. Pending host tool calls
remain valid; their results can start speech in the reseeded local session.
Tool results already queued during a hold remain queued until release.
A second scripted close fails the provider with `:reseed_failed`, matching the
single-replacement limit of GPT-Live. Ordinary Morse sessions reject the
scripted operation.

## Alternatives considered

- Restarting the Morse provider process would make the capability report a
  provider failure before it could exercise continuity. An in-process reset
  matches GPT-Live's replacement-socket behavior at the STS boundary.
- Reusing the GPT-Live fake socket would test the OpenAI adapter again and
  would not independently exercise the local provider's clock and decoder.
- Enabling scripted closes by default would expose test controls to normal
  local calls. The explicit manual-clock option keeps the harness scoped.

## Implications and verification

The harness is deterministic and has no network or credential dependency. It
uses the existing `PublishedHistory` ring, so the same 128-message and
8,192-token bounds apply. It is a local test control, not a production
duration-renewal mechanism. The Morse provider has no connection deadline to
simulate; GPT-Live's fake-socket tests own that check.

The focused duplex capability, conversation and descriptor files passed 33
tests with zero failures. The red tests exposed the absent scripted option and
a pending tool call that became stale after reset. A held tool result also
disappeared in the first reset implementation. Both now survive reseed and
complete under the new local session. The umbrella test run had one unrelated
Gateway WebRTC handoff timeout, which passed when rerun alone. The remaining
umbrella gates and test details are recorded in the milestone and labnotes.
