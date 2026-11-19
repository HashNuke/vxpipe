# Diagnostic audio timeline

- Continuing after7def5cd8 with a clean checkout. Source workers require a verified
  accepted-audio/sample correspondence before emitting acoustic timing results.
- Five timeline tests failed for the missing API; a separate capture regression
  failed because already-decoded Opus was rejected. Added bounded PCM projection
  of decoded Opus, requiring exact timestamp/rate/channel correspondence and
  rejecting extra decoded fields or oversized combined payloads. Compressed bytes
  are not retained in the delivered diagnostic copy. Provider input is unchanged.
- AudioTimeline normalizes only the observer copy via existing STTActivityPCM,
  preserving the source's actual sample continuity checks before conversion.
  Source gaps smaller than one output sample still invalidate prior mapping.
  Accepted PCM duplicates are deduplicated; conflicting duplicates, identity/rate
  changes and out-of-order receipt clocks fail. Millisecond transport receipt is
  explicitly converted to microseconds relative to the run origin.
- Keeps one original-frame metadata entry and bounded normalized mapping history,
  plus a fixed digest instead of prior PCM. Mapping exposes quantization uncertainty
  in addition to receipt jitter. No provider reset or control event is emitted.
- Initial timeline/capture checks12/0. Automatic source workers, Opus decode when
  the transport supplies no existing decoded copy, and full live correspondence
  remain pending; the combined C observation task is not complete.

- Astra proved two gap-reset failures: clearing last_input reassigned an expired
  endpoint to a new receipt timestamp and erased compressed receipt-clock
  uncertainty. Retained red regressions and preserve the prior ordering marker
  while dropping mapping history. A further rounding regression showed source
  uncertainty could disappear when961 samples became320; normalized entries now
  preserve the source uncertainty flag and the larger uncertainty allowance.
- Retained and independent original reproductions pass13/0. The full root run
  started for the prior async-inference checkpoint remains live and has passed
  Engine2615/0; it predates these timeline edits and cannot prove current-source
  milestone acceptance. Final review and focused/static reruns follow.

- Final affected suite95/0; root format, warnings-as-errors compile, strict Credo,
  unused-lock checks and final Lean pass. Astra xhigh re-review clean, independently
  91/0 including both original reproductions and empty-normalization/gap probes.
  No combined C task is checked off: source-worker composition, source-specific
  inference association, raw Opus decoding and configured-call acceptance remain.
