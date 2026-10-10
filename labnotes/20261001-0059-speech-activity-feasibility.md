# Speech activity runtime feasibility

> Relocated from `docs/speech-activity-feasibility.md` on 2026-10-09. First recorded source commit: `8efe486e6537` (2026-10-01T00:59:27+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20261001-0037-speech-activity-feasibility](20261001-0037-speech-activity-feasibility.md), [20261001-0153-local-speech-activity](20261001-0153-local-speech-activity.md).
> Maintained contracts/progress: [elevenlabs-stt-session](../docs/elevenlabs-stt-session.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Status: Local runtime implementation, 2026-10-01. This informs
[ElevenLabs caller STT](20260930-1119-elevenlabs-turn-ownership.md) and
[provider expansion](milestones/provider-expansion-and-ai-gateway.md).
It does not register conversational STT or change shared STS contracts.

## Decision and boundary

Keep Scribe's verified short native VAD segment evidence, while the long-stream
observation leaves commit cause and turn authority unresolved. Investigate
genuine acoustic onset/end separately from recognition settlement. Silero is a
viable candidate for acoustic activity in the tested Python and native Elixir environments.
The pinned model and native bindings are now selected for an allocation-owned
runtime. Packaging and focused runtime checks pass; connection to Scribe, turn
correlation, room admission and deployment acceptance remain pending.

A first transcript partial cannot supply activity evidence. Local acoustic turn
ownership requires explicit provenance and consumer review; native segment
commits alone do not establish a turn boundary. A hosted agent is outside the
user-approved STT/TTS scope. These remain
rejected shortcuts. An activity classifier detects voice, not semantic completion
of a person's thought.

## Reproducible model and runtime inputs

| Input | Pinned value |
| --- | --- |
| Silero source | [v6.2.3 commit 5cd7945](https://github.com/snakers4/silero-vad/tree/5cd7945676eb32225748052e2e6a0580e4686a08) |
| Model | [silero_vad.onnx](https://github.com/snakers4/silero-vad/blob/5cd7945676eb32225748052e2e6a0580e4686a08/src/silero_vad/data/silero_vad.onnx) |
| Model SHA-256 | `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3` |
| Model format | IR 8, ai.onnx opset 16; ONNX checker passes |
| License | [MIT, Silero Team](https://github.com/snakers4/silero-vad/blob/5cd7945676eb32225748052e2e6a0580e4686a08/LICENSE) |
| Reference runtime | Python 3.12, CPU Torch 2.5.1, NumPy 2.2.6, ONNX Runtime 1.19.2 |
| Elixir candidate | [Ortex v0.1.10 commit 450dbe6](https://github.com/elixir-nx/ortex/tree/450dbe6ec6cc96e4e5509a746937ccde25de0144), Nx 0.11.0, Rustler 0.37.3 |

The reference uses the pinned
[upstream wrapper](https://github.com/snakers4/silero-vad/blob/5cd7945676eb32225748052e2e6a0580e4686a08/src/silero_vad/utils_vad.py).
At 16 kHz it consumes 512 new samples and 64 retained context samples, with
separate [2,1,128] recurrent state per stream. Normalize signed little-endian
PCM by 32768.0. Context must not be counted again as accepted input. Model inputs
are ordered input/state/int64 sample-rate; outputs are probability/stateN.
A production integration must pin this identity and package license notices.
No model download or Python process has been introduced into application startup.

## Observed checks

Using the existing committed 66,560-sample public speech fixture:

- The isolated NumPy owner matches the official Torch wrapper exactly over 130
  frames. Irregular PCM splits, including odd byte boundaries, preserve output
  and sample accounting. Reset restores the reference result.
- At probability >= 0.5, 52 speech frames classify as voice. Zero silence, seeded
  white noise and a 440 Hz tone have none. These controls cover three bounded
  negative cases, not a general acoustic quality or false-activation guarantee.
- Sixty-four separate Python stream states with sixteen workers and one shared
  CPU inference session preserve reference results. Processing 266.24 seconds of
  audio takes 1.3523 seconds, with explicit intra/inter thread settings of one.
- An unpatched native Ortex build completes with the umbrella's Nx/Rustler versions.
  All 130 Elixir frame probabilities match the Python reference exactly.
- Sixty-four native stream states and sixteen Task workers share one model and
  retain exact speech results while rejecting silence, completing in 2.476193
  seconds. Process thread counts are 24 before load and 27 after load/processing.

The native source uses dirty IO scheduling for inference and does not expose
explicit thread tuning in its load API. The native thread observation is host
specific; Python's configured thread limit is not an Elixir runtime guarantee.
The upstream Model Inspect implementation fails with current Elixir's algebra
return shape; the probe avoids inspecting that resource. The probability output
must be reshaped from [1,1] to a scalar before Nx.to_number. Neither diagnostic
issue required patching native inference.

See [experiment labnotes](20261001-0037-speech-activity-feasibility.md)
for failed setup attempts, runtime versions, controls and verification details.
The initial experiments remain isolated. The local runtime checkpoint below
adds the pinned native dependency and model to the owning application.

## Allocation-owned runtime checkpoint

CallEngine directly owns Nx 0.11.0 and the pinned Ortex revision. The unmodified
model and MIT notice are packaged under `priv/speech/`; loading verifies its
SHA-256 digest. Startup performs no download or model load. A named lazy cache
retains only the public CPU resource; it receives no PCM or per-stream state.
An allocation's `ActivitySupervisor` owns its runtime and task supervisor, with
one inference slot by default and no waiting audio queue. Starting this helper
under the actual Scribe allocation remains part of session integration.

The stream accepts at most 32,000 bytes of aligned 16 kHz PCM per request and
retains fewer than 1,024 incomplete bytes. Complete 512-sample frames use explicit
little-endian normalization and private recurrent/context state. No incomplete
frame is padded or counted as silence. Reset discards all previous stream state.

`ActivityBoundary` requires four consecutive frames at probability >= 0.5 for
onset (128 ms), and sixteen frames below 0.35 for endpoint (512 ms). Hysteresis
or resumed voice clears pending silence. Boundaries identify the initial sample
of the confirmed interval; confirmation arrives later. These fixed acoustic
thresholds do not establish semantic completion and expose no public tuning.

Admission returns busy without accepting more work. Accepted tasks are monitored
against their caller, use fixed safe error reasons and have separate 15-second
initialization and 2-second warm inference deadlines. Cancellation requests task
termination but retains its slot until task settlement; killing an Elixir process
does not guarantee interruption of an in-progress native call. A `one_for_all`
tree retires local workers after runtime failure. Another allocation's worker
continues. Total concurrency follows active allocation count; this is not a
machine-wide four-worker pool or an application-wide speech execution queue.

Rejected alternatives: per-call model loading duplicates native resources;
unbounded asynchronous submission retains arbitrary PCM; sharing private workers
globally couples allocation failures; interpreting missing frames as silence
fabricates evidence. A separate Python process would add deployment and lifecycle
responsibilities already served by the verified native binding.

Twenty-three focused checks pass, seed 865692. Native probabilities match the
stored official-wrapper reference within 1e-6, independent of chunking or reset.
The public speech fixture supplies one actual acoustic onset/end through the
supervised runtime. Silence, a bounded tone and seeded noise supply negative
controls, not a general false-activation or natural-conversation quality claim.
Only Linux x86-64 native compilation/inference is verified on this host. Other
deployment targets and realistic acoustic coverage remain open. All five root
gates pass: 2,997 default tests, zero failures, 92 exclusions, seed 936184. The
existing Lean model/replay lane also passes; it does not add a formal model of
this private classifier. No conversational STT capability is registered by this checkpoint.
See [runtime labnotes](20261001-0153-local-speech-activity.md).

## Required integration gates

- [x] Pin and inspect model, checksum, license and ordered tensor shapes.
- [x] Compare normalized CPU inference with the upstream wrapper on one public fixture.
- [x] Verify reference chunk splitting/reset and native independent stream states.
- [x] Build and execute the native Elixir candidate with the umbrella's library versions.
- [x] Establish complete-frame accounting, confirmation/hysteresis and bounded negative controls.
- [x] Package the pinned model/notices without startup downloads.
- [x] Implement bounded allocation-owned inference, deadlines, cancellation and failure supervision.
- [ ] Verify supported deployment targets and realistic acoustic coverage beyond the tested host/fixture.
- [ ] Reset activity state across permission intervals, allocations and participant changes.
- [ ] Review local acoustic boundaries, serialized recognition and delayed-event correlation.
- [ ] Verify session, room, scoped publication, Console and live conversational acceptance.

Delayed native commits cannot be assigned to a later turn solely by receipt time.
Long-input endpoint identity remains separate from activity-start feasibility.
Optional finite-input agent-output recognition is outside caller STT prerequisites.
The milestone remains in progress until actual integration and acceptance pass.

The [controlled recognition checkpoint](20260930-1119-elevenlabs-turn-ownership.md#controlled-manual-recognition-assembly--2026-10-01)
passes eighteen owning local checks and one selected two-segment manual wire
case. It supplies a boundary explicitly and does not implement or validate this
acoustic classifier. Its bounded assembly is preparation for the composed session.
