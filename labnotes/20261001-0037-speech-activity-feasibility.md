# Speech activity feasibility

## Intent and boundary

Scribe native VAD commits have one short passing live observation, but its
public protocol has no genuine activity-start event. Investigate only the missing
local activity responsibility before changing STT admission. Preserve valid native
endpointing; no hosted-agent STS work or provider capability registration follows
from this experiment. Python inference cannot establish Elixir runtime acceptance.

## Artifacts and environment

The pinned Silero v6.2.3 tag resolves to commit
`5cd7945676eb32225748052e2e6a0580e4686a08`. The ONNX artifact fetched both by tag
and immutable commit is byte-identical. Model SHA-256 is
`1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`;
the upstream wrapper SHA-256 is
`15d0f6b3ef9590e22ca2f146e1436f6901da356cb552d3183df4100862b333cb`.
The immutable license says MIT, copyright 2020-present Silero Team.
The ONNX checker passes: IR 8, ai.onnx opset 16, 2,327,524 serialized bytes.

The system Python venv attempt fails because ensurepip is unavailable. uv first
selects Python 3.13, for which ONNX Runtime 1.19.2 has no wheel. Selecting installed
Python 3.12 explicitly resolves this. The isolated temporary environment uses
ONNX Runtime 1.19.2, NumPy 2.2.6, ONNX 1.17.0 and CPU-only Torch/Torchaudio 2.5.1.
No package, model or fixture is added to project dependencies or downloaded at
application startup. No API credential or billable request is used.

## Probe and observed results

Inspecting the loaded CPU model establishes ordered inputs: input float tensor,
state float tensor [2,batch,128], sample rate int64 scalar; outputs are probability
and stateN. Each 16 kHz step accepts 512 new samples plus 64 samples of retained
context. Context is not counted again in accepted audio.

An isolated NumPy state owner feeds the same frames as the pinned official
OnnxWrapper with Torch. On the existing public Deepgram fixture (66,560 samples,
130 frames), maximum absolute probability difference is exactly zero. Splitting
PCM into irregular chunks including odd byte lengths, then reframing complete
512-sample steps, gives identical probabilities and exact sample accounting.
Reset restores the initial state and the reference result.

At probability >= 0.5, the speech fixture has 52 classified frames, peak 0.999998.
Equal-length zero silence has no classified frames, peak 0.008911. Seed-1234
Gaussian white noise (0.15 scale) has none, peak 0.015610. A 440 Hz sine (0.3
amplitude) has none, peak 0.003323. These synthetic negative controls are not a
real acoustic quality corpus or a general false-activation guarantee.

One shared ONNX session uses explicitly configured intra/inter thread counts of
one. Sixty-four independent streams (alternating speech/silence), with sixteen
Python executor workers, retain exact reference speech probabilities and reject
silence. All preserve 66,560 accepted samples. Aggregate 266.24 seconds of audio
processes in 1.3523 seconds. Process thread count is four before and six after the
executor exits; this is an observation, not a guarantee that all libraries leave
one native thread or a production concurrency benchmark.

The temporary probe is not shipped product code. Reproduction must use the pinned
artifact/checksum, upstream wrapper and runtime versions, the committed 16 kHz
fixture, little-endian signed PCM normalized by 32768.0, separate zero state and
64-sample context per stream, and complete 512-sample steps. The same seeded
noise/tone and worker/sample counts above describe the bounded experiment.

## Decision and next gates

Silero is feasible as a candidate in an isolated CPU Python experiment. It is not
a selected Elixir dependency, supervised detector or admitted Scribe STT session.
Verify an Elixir runtime's model execution, thread/buffer/resource bounds,
supervision and cancellation before selecting it. Check activity confirmation
against realistic noise and telephony fixtures. Review local-onset/native-end
turn identity explicitly; delayed native commits cannot be assigned to a later
caller turn by arrival timing alone. Keep long-input endpoint evidence and
optional agent-output drain separate. Preserve exact provider/model usage identity
and honest activity provenance. No shared STS contract changes are proposed.

## Elixir runtime probe

The immutable Ortex v0.1.10 source resolves to commit
`450dbe6ec6cc96e4e5509a746937ccde25de0144`. An isolated temporary Mix project pins
Nx 0.11.0 and Elixir Rustler 0.37.3, matching the umbrella versions. Its locked
native Rustler is 0.29.1 and ort/ort-sys is 2.0.0-rc.8. Dependency retrieval and
native release compilation complete with one Cargo build job. Upstream Rust
lifetime warnings appear; no warnings-as-errors claim is made for this independent
vendor build. The umbrella and its dependency lockfile remain unchanged.

The first inference probe has two diagnostic errors: upstream Model inspection
is incompatible with the current Inspect.Algebra return shape, and Nx.to_number
requires a scalar rather than a [1,1] probability. Avoiding model inspection and
explicitly reshaping that probability resolves the diagnostic mistakes; no vendor
source is patched. All 130 fixture frames then match the official Python wrapper
with maximum absolute difference exactly zero and 52 frames >= 0.5.

A second native experiment shares one loaded model among sixty-four stream-local
state/context reductions, sixteen bounded Task.async_stream workers, alternating
speech and silence. Every 130-frame speech result matches its reference; silence
has no classified frames. It completes in 2.476193 seconds, maximum difference
zero. Observed BEAM process threads rise from 24 before model load to 27 after
load and remain 27 after processing. These are this host's counts, not configured
thread limits or a full production load benchmark. Stock Ortex exposes execution
providers/optimization but no explicit intra/inter thread controls; the Python
one-thread profile must not be attributed to this native experiment.

This establishes build and recurrent-state execution compatibility for the tested
Linux/Elixir/OTP/runtime combination. It leaves model distribution/notices,
startup ownership, scheduler/backlog limits, other deployment targets, realistic
acoustic quality, and local-onset/native-end turn correlation unimplemented.
Select no new project dependency or STT capability yet. All five root gates for
the separately committed Scribe VAD checkpoint pass; no repeat is needed for this
documentation-only experiment record. Pushnotify records actual checkpoint and
remaining integration work.
