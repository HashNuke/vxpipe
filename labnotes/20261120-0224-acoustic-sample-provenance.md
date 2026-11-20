# Acoustic sample provenance

2026-11-20: acquired two small real human speech recordings, froze visually
reviewed uncertainty bands, and added reproducible controlled cases and an
evaluator. The acquisition notes below record the initial temporary artifacts;
the later checkpoint includes the attributed source WAVs in repository fixtures.
No provider or native detector execution is claimed by this checkpoint.

## Source and permission

[Open Speech Repository American English source](https://www.voiptroubleshooter.com/open_speech/american.html)
identifies female and male 16-bit PCM, 8 kHz Harvard-sentence recordings. Its
explicit conditions permit research, download, copying, modification and inclusion
in products, with attribution to "Open Speech Repository". This is the source's
custom attribution permission, not a claim of CC licensing. Its
[contributor policy](https://voiptroubleshooter.com/open_speech/contribute.html)
requires speaker releases. No fee or account was required. Generic site terms
outside the Open Speech section differ; use this speech-specific source notice.

Fetched 1,288,900 bytes total, no archive or bulk corpus:

| Recording | Bytes | Frames at 8 kHz | SHA-256 |
| --- | ---: | ---: | --- |
| OSR_us_000_0010_8k.wav (female) | 538014 | 268985 | a4bf9becd046d7aedb6d05b6e12347a6294a44f74d263089c636fb0a2b1e6561 |
| OSR_us_000_0030_8k.wav (male) | 750886 | 375421 | d3e1cfba98a44ddfc6e99508e663794c8dc41bdb2baced224f779c453143b622 |

Direct URLs use `https://voiptroubleshooter.com/open_speech/american/` followed
by the filenames above. Initial requests to the www hostname returned HTTP406;
the canonical bare hostname served the files. Python standard-library WAV parsing
verified mono, 16-bit, 8 kHz; full durations 33.623125 and 46.927625 seconds.

## Visual candidates, not frozen truth

Temporary directory: `/tmp/vxpipe-acoustic-acceptance-osr`. It contains source WAVs,
`manifest.json`, `candidate-labels.json`, plotting scripts, overview/detail PNGs.
Plot dependencies were isolated using uv cache there; audio download bound was
2 MB per file. Visuals show time-labelled waveform and 16 ms-window spectrogram.
The detail plots shade the candidate intervals cyan. No listening occurred and
no VAD model output was obtained or consulted.

Agent visual inspection proposes first-utterance intervals in original source time:

| File suffix | Onset interval | End interval | Limitation |
| --- | --- | --- | --- |
| 0010 | 0.505–0.525 s (samples4040–4200) | 2.84–3.03 s (22720–24240) | Background and low-level transient near2.995 s make end ambiguous; do not claim a precise midpoint. |
| 0030 | 1.967–1.977 s (15736–15816) | 4.62–4.70 s (36960–37600) | Quiet harmonic tail gradually merges with background. |

The male clip's internal pause around3.75–4.0 s is inside this candidate sentence
span. Within-word/phoneme quiet periods must not be labelled as separate user
turns merely because amplitude falls. First sentence is a visual grouping, not
a transcript/listening-confirmed conversational turn. Root must independently
review plots and freeze or revise intervals before any native inference.

Compare inferred boundaries to intervals, including signed possible-error range,
instead of inventing sample-exact human truth. Keep label revision provenance and
hash frozen manifest before running the detector. Resampling to16 kHz later must
preserve timing with documented sample mapping; upsampling does not create new
bandwidth or shrink uncertainty.

## Limits and next action

These are real human read narrowband English, not natural conversation and not
pre-existing human-labelled acoustic ground truth. They can support a small
visually reviewed reference pilot after review; they cannot justify universal
accuracy or claim all six natural-condition categories are covered.

Controlled noise/echo/agent-overlap/pause-resumption variants can retain these
clean stems and aligned intervals, with explicit transform parameters and honest
synthetic-condition labels. Agent reference playback must remain distinguished
from caller speech. No variants created yet. Parent owns review, freeze, detector
runs and any milestone scope/evidence decisions. Main deliverable is usable small
source material and inspectable candidate intervals, not an accuracy result.

## Frozen reference and reproducible pilot implementation

Parent independently inspected both overview/detail images and approved the exact
bands without listening or detector output. Froze `reference.json` and SHA256
`a2d9d0137dca2972bc99769f43407aac1a1027e91e36da2db97248c9c31f4bf6`
in `apps/vxpipe_call_engine/test/fixtures/speech/acoustic_acceptance/`, alongside
original source WAVs and speech-specific attribution/provenance README.

Added `scripts/diagnostics/acoustic_acceptance.py` and six focused tests. Red:
`python3 -m unittest discover -s scripts/diagnostics -p test_acoustic_acceptance.py`
failed with expected missing module. Green after implementation: six tests pass.
Tests cover interval-valued signed/absolute error, missing/open boundaries,
internal segmentation, invalid chronology, exact coordinate translation and
reproducible controlled variants/separate overlapping voice stem.

Generator emitted12cases(two speakers×six conditions) in temporary controlled
output. Conditions are clean, quiet-tail attenuation, seeded noise, delayed echo,
overlapping other speaker and pause/repeat. Each manifest records exact labels,
transforms, PCM hashes and source reference hash. Source-to16kHz conversion is
explicit linear2×; original samples map to even output samples. All labels are
clean direct caller reference bands, including for transformed mixtures.

Parent correction applied: male internal pause can legitimately create multiple
acoustic segments. Evaluator compares outer boundaries and reports internal
segmentation separately, never invents false positives from sentence grouping.
No native inference/provider/Mix run performed. Native lane remains another
agent's ownership. Artifacts are a visually reviewed controlled pilot, not an
assertion that milestone natural/live accuracy acceptance is complete.

Parent review found two evaluator gaps: outside segments were called internal,
and pause/resume scoring omitted its internal boundaries. Added tests first;
red produced two missing-key errors and a nonfinite-validation failure. Updated
matching to preserve raw segments, report outside indices, identify outer matched
indices, and retain every plausible internal boundary candidate with explicit
unique/missing/ambiguous status. Added finite-number checks rejecting NaN/Inf,
booleans and strings. Nine focused tests now green. Generated controlled manifest
now includes internal pause/resumption reference bands; frozen source reference
hash unchanged. No detector executed.

Independent reviewer reproduced a frozen-label integrity gap: source checksums
were verified but reference.sha256 was only recorded, not enforced. Added a test
that changes label coordinates in an isolated copied corpus while retaining the
old digest: red failed because generation accepted it. Build now verifies the
frozen reference digest before creating any output directory. Ten tests green.
No reference bytes or frozen labels changed; no detector executed.

Second review reproduced independent internal candidates describing one segment
in reverse end/onset order. Added regression first (red: missing pair field).
Internal reports now preserve all candidates and separately enumerate only pairs
with strictly increasing segment indices and sample coordinates, with explicit
missing/unique/ambiguous pair status. Eleven focused tests pass. A lone segment
inside the pause cannot become a valid end/resume pair.

Final GPT-6 Astra xhigh re-review is clean. Its independent 11-test run and two
full builds confirm both corrections, unchanged reference hash, and identical
12-case PCM hashes. Native per-mode accuracy remains the next separate task.
