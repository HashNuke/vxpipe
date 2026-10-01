# ElevenLabs native VAD preparation

## Intent and contract review

The user selects Scribe Realtime or another suitable ElevenLabs realtime model
and expects provider turn detection. Prior documentation foregrounded a local
detector composition prematurely. The revised input-turn proposal assesses native
VAD first, keeps provider endpointing when valid, and separates missing speech
onset from turn end. No batch-only substitute, shared speech-contract change or
local detector dependency is introduced.

The current official commit guide documents silence-triggered commits in VAD
mode. Its approximately 36-second automatic commit explanation appears under
manual mode; behavior in VAD mode remains unestablished. The public event guide
documents stable segment events and explicitly excludes a separate final event;
it does not expose speech-start. A transcript partial still cannot become genuine
barge-in evidence. Optional finite-input drain is not a caller STT prerequisite.
Sources and rejected alternatives are linked in the updated design document.

## Red-green implementation

The existing five Scribe codec/configuration tests first pass in a direct offline
ExUnit invocation, seed 950184. Four new tests then fail for the expected missing
VAD constructor option, absent mode-aware decoder, rejected VAD acknowledgement,
and missing startup validation: nine tests, four failures, seed 533946.

The closed configuration accepts only `:manual` and `:vad`; manual remains the
default. The request uses the selected wire strategy, while the socket carries
its expected acknowledgement mode privately. Returned optional configuration
fields still must match whenever present. Unknown modes fail before connection;
committed text remains a segment without manufactured speech events. Credential
inspection/header privacy remains covered.

The final focused invocation loads current credential/Scribe/socket sources,
with only the unchanged Socket behaviour available from its compiled module.
It passes nine tests, zero failures, seed 980595, without warnings. An earlier
invocation exposing the entire old application beam directory produced module
redefinition/stale export warnings; limiting the code path to the one unchanged
behaviour removes that ambiguity. No network or Mix startup is used by the
focused checks; this is not an umbrella compilation or integration gate.

## Selected live case and limitations

A separately selectable VAD case is written at the Scribe protocol test's line
45. It requests VAD, streams the existing sample plus two seconds of paced
silence, submits under ten seconds of audio, and expects the known final word
without a manual commit. The manual case remains independently selectable at
line 12. Neither case is run during this checkpoint. No provider request or
billable model call is made. A short result would establish automatic segment
finalization only, not long-input turn boundaries or speech onset.

The current focused Mix command and root warnings-as-errors compilation/strict
Credo fail at Mix.PubSub TCP startup with `:eperm`. The unused-dependency gate
fails at its TCP-based lock for the same restriction. Format succeeds. Default
umbrella and socket/live integration acceptance remain unavailable; no source
cutover or speech state machine is changed, so the Lean lane is not required here.
There is no scoped STT registration or UI change to inspect.

The environment declares Git metadata read-only and disallows escalation, so
this checkpoint is not staged, committed or pushed. Preserve it separately from
the withdrawn tool-resource investigation and preserve the unrelated user content
configuration edit. Pushnotify succeeds for the current progress update.

Next: once TCP execution is permitted, run the owning codec/socket suite and
only the new VAD live case, then establish long-input endpoint and genuine onset
contracts before room admission. ElevenLabs conversational realtime STT remains
required; hosted-agent STS is deferred by the user-approved 2026-10-01 STT/TTS-only
scope. The milestone stays unchecked. No shared STS contract changes were made.

After the STT/TTS scope cleanup, the same nine current-source offline checks pass
again, seed 673268. Format and diff checks pass, as does direct static Credo on
1,167 current source files. This does not replace the unavailable Mix/live gates.
The three investigation labnotes distinguish withdrawn agent prototypes from
retained Scribe protocol work; no passing paid case is repeated.
