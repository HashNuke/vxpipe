# Speech activity runtime feasibility

Status: Isolated research, 2026-10-01. This informs
[ElevenLabs caller STT](elevenlabs-turn-ownership.md) and
[provider expansion](milestones/provider-expansion-and-ai-gateway.md).
It does not register conversational STT or change shared STS contracts.

## Decision and boundary

Keep Scribe's verified short native VAD endpointing and investigate the missing
genuine activity-start responsibility separately. Silero is a viable candidate
for that responsibility in the tested Python and native Elixir environments.
Its runtime is not yet selected for production: startup/distribution ownership,
bounded execution and turn correlation still need implementation and acceptance.
The existing detector fallback design remains conditional.

A first transcript partial cannot supply activity evidence. Replacing valid
native endpointing with local silence ownership would introduce a larger contract
change. A hosted agent is outside the user-approved STT/TTS scope. These remain
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

See [experiment labnotes](../labnotes/20261001-0037-speech-activity-feasibility.md)
for failed setup attempts, runtime versions, controls and verification details.
Model/runtime artifacts and experiments remain isolated from project dependencies.

## Required integration gates

- [x] Pin and inspect model, checksum, license and ordered tensor shapes.
- [x] Compare normalized CPU inference with the upstream wrapper on one public fixture.
- [x] Verify reference chunk splitting/reset and native independent stream states.
- [x] Build and execute the native Elixir candidate with the umbrella's library versions.
- [ ] Establish incomplete-frame behavior, confirmation/hysteresis and realistic acoustic coverage.
- [ ] Package model/notices and verify supported deployment targets without startup downloads.
- [ ] Bound scheduler time, concurrency, backlog and failures under an owned supervised runtime.
- [ ] Reset activity state across permission intervals, allocations and participant changes.
- [ ] Review local-onset/native-end turn identity and delayed-event correlation.
- [ ] Verify session, room, scoped publication, Console and live conversational acceptance.

Delayed native commits cannot be assigned to a later turn solely by receipt time.
Long-input endpoint identity remains separate from activity-start feasibility.
Optional finite-input agent-output recognition is outside caller STT prerequisites.
The milestone remains in progress until actual integration and acceptance pass.
