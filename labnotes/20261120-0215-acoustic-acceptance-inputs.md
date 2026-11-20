# Acoustic acceptance inputs

2026-11-20: read-only audit for passive-call-latency-diagnostics milestone E/F.
No tests, native inference, provider calls, downloads or deployments run. No
credential file read or modified. CPU overhead remains advisory per user decision.

## Existing evidence and missing ground truth

- `docs/design/latency-diagnostics-measurement-plan.md:377` requires independently
  labelled quiet tails, pauses, noise, echo, overlap and resumption; report signed
  and absolute boundary error and incomplete rate separately by mode/condition.
- `apps/vxpipe_providers/test/fixtures/deepgram/README.md` documents generated
  public speech: `short_answer_16k_mono_s16le.pcm` ("Yes.", 600 ms) and
  `final_word_16k_mono_s16le.pcm` ("The final word is telescope.", 4.16 seconds,
  including appended silence). Neither supplies independently reviewed onset/end
  labels. These are TTS samples, not recordings of human conversation.
- `apps/vxpipe_call_engine/test/fixtures/speech/README.md` documents the Silero
  official-wrapper probability reference. It validates tensor/state assembly,
  not acoustic ground truth.
- `scripts/diagnostics/replay_latency.exs:81` derives a reference endpoint from
  Silero, then positions synthetic provider events relative to that endpoint.
  This proves integration/reporting, not detector accuracy or live STT latency.
- `acoustic_replay_test.exs` tests native replay, duplicate-frame equivalence and
  audio-gap evidence. It does not compare native endpoints with human labels.
- Repository file-name searches found no TextGrid/RTTM or boundary-label CSV/JSON
  corpus. Existing synthetic marker/barge fixtures cannot close this accuracy gate.

## Smallest practical accuracy path

Use a small, fixed set of real caller speech clips, independently annotate their
onset/end in sample coordinates by listening plus waveform/spectrogram inspection,
then run both operational-reuse and fallback Silero against exactly that PCM.
Annotators must not see detector output before freezing labels. Record ambiguous
boundary intervals rather than claiming sample-perfect truth. Store source,
license/permission, sample rate, checksum, condition, onset/end and uncertainty.
Use at least one clip per required condition; this is bounded acceptance evidence,
not a universal model-accuracy guarantee.

Existing supplied PCM can bootstrap the annotation/replay plumbing without a
provider request. Independently label the actual acoustic boundaries, never the
file length or appended-silence boundary. This still only establishes synthetic
voice accuracy; it cannot support a claim about human quiet tails or natural
pause/resumption. A short permissioned human recording set is the smallest direct
way to supply those missing conditions.

For controlled noise/echo/overlap variants retain the clean caller stem and frozen
human labels as the reference, with documented transformation and alignment.
Agent playback stays a separately identified stem; agent speech must not become
the human label. Explicitly distinguish controlled mixtures from real browser
acoustics. Count missed, unmatched, extra and ambiguous boundaries rather than
silently excluding them. Compare acoustic endpoint error separately from actual
end-to-STT-turn-end and onset-to-agent-stop delays.

## Bounded primary-source corpus check

- [LibriSpeech/OpenSLR](https://www.openslr.org/12/) supplies human audiobook
  speech under CC BY 4.0. Smallest listed clean development archive is 337 MB;
  no listed purchase fee. No archive downloaded. A tiny selected subset could be
  independently labelled, but its supplied transcript/segmentation is not proof
  of precise VAD boundaries. It supplies human read speech, not guaranteed echo,
  agent overlap or conversational resumption. These need separately documented
  controlled variants or permissioned captures.
- [Published LibriSpeech alignments](https://zenodo.org/records/2619474) are
  Montreal Forced Aligner output. Do not relabel these as human-reviewed acoustic
  truth; this would substitute another model for independent labels.
- [QUT-NOISE](https://github.com/qutsaivt/QUT-NOISE) is CC-BY-SA noise with
  BSD-style preparation code, but constructing QUT-NOISE-TIMIT requires an existing
  local TIMIT installation. No such local resource was found in repository files.
  It adds acquisition/licensing dependencies and is not the minimal completion
  path. No bulk corpus acquisition recommended for this milestone.

## Existing live commands and their limits

Commands below are identified from source, not executed:

```sh
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_speech_to_text_test.exs
bin/livetests run --only live_elevenlabs apps/vxpipe_console/test/integration/elevenlabs_configured_room_test.exs
```

First lane exercises actual Scribe STT recognition (short answer, distinct/repeated
turns, initial idle/silence). Second exercises a configured room with encrypted
credential provisioning and one long automatically segmented caller turn.
Neither is the complete diagnostics-on operational-VAD-off/on browser acceptance
matrix, and neither by itself measures all required normal/pause/barge/tool-end/
hangup scenarios or validates persisted acoustic diagnostics against labels.

Prerequisites: normal checkout dependencies/database/model setup and existing
runner-provided ElevenLabs credentials. Deepgram fixtures are already present;
fixture helpers can invoke Deepgram TTS if files are missing, so preserve them.
Do not inspect the credential file to determine availability. `bin/livetests:572`
selects telephony only for telephony/Twilio/Telnyx arguments (or no arguments);
the explicit commands above bypass carrier provisioning and Funnel setup. Never
invoke the runner with no selection for this task.

The production settings browser check is separately local:

```sh
cd apps/vxpipe_console
mix test --include integration test/integration/diagnostics_settings_browser_test.exs
```

It needs built Console assets, local test DB, `agent-browser`, Chrome and `setsid`;
it starts a loopback Bandit server with synthetic identity state. It has only the
integration tag and is not live Scribe/browser-media acceptance. Satisfying F
still requires the focused tagged configured diagnostic browser-media scenario,
both VAD modes, persisted/UI comparison and permitted independent audio labels.

## Handoff

Main blocker is independent acoustic labels, not CPU optimization or a new large
benchmark framework. Do not check E/F complete from existing replay/adapter tests.
Parent owns milestone updates and any subsequent implementation/run decisions.
