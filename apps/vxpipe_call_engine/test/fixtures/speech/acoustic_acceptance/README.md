# Small acoustic reference pilot

Source: **Open Speech Repository** (required attribution).

- [Original recordings and speech-specific permission](https://www.voiptroubleshooter.com/open_speech/american.html)
- [Contributor release policy](https://voiptroubleshooter.com/open_speech/contribute.html)

The speech-specific permission allows research, download, copying, modification
and redistribution with source attribution. It is custom attribution permission,
not a Creative Commons designation. Both recordings are human readers of Harvard
sentences, mono signed 16-bit PCM at 8 kHz. `reference.json` records original URLs,
full-source checksums, chosen crops and original-sample reference bands.

## What these labels mean

Two agents inspected waveform and spectrogram plots independently of Silero
output; neither listened. The reviewing agent approved the uncertainty intervals
on 2026-11-20 before any detector was executed on these clips. `reference.sha256`
freezes that artifact. They are **visually reviewed acoustic reference bands**,
not human-listening annotations, exact phonetic boundaries, or natural browser
conversation ground truth. The female endpoint intentionally has 190 ms uncertainty
because a late transient cannot confidently be classified visually.

Score outer onset/end only; report internal detector segmentation separately.
The male sentence has an internal pause: splitting it into multiple acoustic
segments is not automatically a false positive or a conversational turn error.
The uncertainty interval must survive evaluation. A zero minimum possible error
only means the detected point lies within the band; it does not prove zero error.

## Reproduce controlled variants

From the umbrella root, without providers, Mix, native inference or dependencies:

```sh
python3 scripts/diagnostics/acoustic_acceptance.py --output /tmp/acoustic-pilot
python3 -m unittest discover -s scripts/diagnostics -p test_acoustic_acceptance.py
```

The generator verifies source hashes, crops one outer utterance per speaker,
linearly upsamples 8→16 kHz (exact source samples at even output indices), and emits
raw 16 kHz mono s16le PCM plus a manifest. Upsampling does not improve source
bandwidth or reference precision. Each case records its checksum, transformed
bands, sample count and transform parameters:

- `clean`: unchanged crop.
- `quiet_tail`: gain 0.15 from 250 ms before the lower endpoint bound onward.
- `noise`: deterministic seed 20261120 uniform noise, peak 300 PCM units.
- `echo`: 100 ms delayed caller copy, gain 0.3; labels remain direct caller speech.
- `overlap`: other human speaker's separately saved aligned stem, gain 0.5;
  labels remain the caller's. This is simulated agent playback, not a live agent.
- `pause_resume`: repeat caller after 1 second inserted silence; outer end moves
  by the second-copy offset. Internal end/resumed-onset reference bands remain
  in transform metadata. Existing crop silence also contributes to the gap.

These controlled conditions exercise noise, echo, overlapping voice, quiet tail
and resumption without claiming natural conversational coverage. A small pilot
cannot establish general accuracy. Echo/noise/overlap boundaries refer to the
clean direct caller stem, not every sound in the mixed signal.

`evaluate(reference, segments, sample_rate)` accepts ordered detected acoustic
segments with sample-coordinate `onset` and `end` (`None` for an unfinished final
segment). It returns possible signed/absolute error ranges, incomplete indicator
and internal segment count. Run it separately per case and mode. Its incomplete
indicator is a case-level value; aggregate case counts explicitly. Keep raw
segments and provenance beside reports; do not discard missed boundaries.

Production source filtering (caller PCM only, never mixed room output), STT-turn
end latency, agent-stop latency, provider acceptance and browser behavior remain
separate gates. This pilot supplies no live latency measurements.

Matching retains raw detections and explicitly reports segments wholly before or
after the reference envelope. Remaining outermost segments supply outer errors;
their indices are included. These outside counts are observations, not validated
false-positive labels. For `pause_resume`, the reference also includes first-end
and resumed-onset bands. The evaluator reports all chronological candidates in
explicit matching windows, each with interval-valued error. Multiple plausible
candidates remain ambiguous; missing candidates remain missing. No nearest-only
selection hides inconvenient detections. The outer incomplete indicator does not
include those internal matching statuses; inspect them separately.

Internal boundary candidate statuses alone do not establish a pause/resume pair.
`chronological_pairs` requires first-end from an earlier segment and an earlier
sample than resumed-onset; `pair_status` explicitly reports whether a complete
pair is missing, unique or ambiguous. Reference digest enforcement happens before
creating generated outputs; changed labels require a deliberate new freeze.
