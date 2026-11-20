# Reuse coverage residual

The final reuse live report had five rows, zero numeric endpoints, and one numeric interruption delay. Endpoint reasons were `inference_reset` or `partial_start`. That summary alone does not reveal whether finalization lacks an unclassified sub-window tail, whole inference windows, a pending boundary candidate, or a genuine source hole.

The exact coverage comparison is:

- Provider source frontier E = provider mapping source origin + provider accepted samples at receipt - provider mapping origin.
- Inference processed frontier P = epoch sample origin + ActivityBoundary.samples.
- Finalized frontier F = P - 512 * max(speech_frames, silence_frames).
- LiveReport requires the selected endpoint and E to lie within the same epoch, with E <= F.

Silero processes complete 512-sample windows and retains fewer than 512 samples as pending PCM. Scribe snapshots accepted sample count when receiving endpoint evidence; normalized browser frames commonly contribute 320 samples. Even ideal processing can leave E - F between 1 and 511. In-flight or queued work can make that deficit larger. ConversationalSTT resets the stream and pending PCM at settlement; SourceWorker discards old queued/late-epoch inference. None of these operations classify the missing suffix.

When silence is already fully confirmed and there is no pending onset, both boundary counters are zero: F already equals P, so a clean reset cannot safely advance it further merely by re-labeling observed silence. When a boundary candidate is pending, increasing F would discard that candidate's uncertainty. Neither case proves the unclassified suffix silent. No production guard was lifted.

Existing focused regression already exercises the exact small-tail case: E = 11,200 and F = 10,752, a 448-sample residual. A clean reset keeps that endpoint unavailable and rejects later progress into the closed epoch. Complete coverage remains measurable. Focused clean-reset/boundary coverage verification passed: 15 tests, seed 800130.

Recommended bounded live metadata, before teardown, for at most five provider-end rows: mapped E, endpoint sample/epoch, matching progress origin/F, E-F, closed reason and nearest reset epoch/reason/time. Snapshot the corresponding worker's processed sample count, speech/silence counters, speaking flag, accepted audio frontier and queued-reuse count. If needed capture only operational stream sample count, pending byte counts and in-flight epoch at settlement. Never include audio, probability arrays, transcript or request payloads. This distinguishes quantization remainder from lag, candidates and holes without broad instrumentation or changing acceptance guards.

## Endpoint-specific proof candidate

The parent clarified a narrower observable: the latest detector `speech_ended` sample at or before E. From a known non-speaking state with no pending onset at P, an unclassified suffix shorter than one 512-sample window cannot create a new `speech_ended` within that suffix: a new speaking state first needs four high windows, and its subsequent ending starts later than P + 2,048. This is an endpoint-stability argument, not evidence that the suffix is silent and not a reason to advance general finalized coverage. Current reset packets do not carry the exact boundary state or accepted-source residual needed for this certificate. Any future application must keep gaps, epoch ownership and pending-candidate checks explicit, and address whether a later-confirmed onset inside the suffix affects ambiguity.

Astra also identified a timing question to measure: the provider receipt timestamp is taken in ScribeSocket, while `accepted_samples` is read later in ContinuousSTT when handling that receipt. Additional admitted audio between those events could inflate E beyond the measured receipt interval. No conclusion is drawn without correlated timestamp/cursor evidence.
