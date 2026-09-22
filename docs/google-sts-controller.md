# Google STS controller boundaries

Status: sequential controller checkpoint implemented locally. Google STS remains unadvertised;
fake-wire acceptance is not hosted interoperability or interruption-history proof.

## Evidence and decision

The shared engine admits an output after its provider reports caller turn end.
The adapter previously used model `turnComplete` for that report, delaying
admission until the response had already finished and exhausting pre-admission
audio buffering. Raw server activity start/end are the caller-control evidence;
transcription or model completion cannot substitute for them.

Keep caller activity end, model generation completion and local sink playback
separate. Use raw activity end to report caller completion and let the existing
engine authorize the output. Model generation completion settles generated data;
publication still waits for selected text and matching playback. Duplicate caller
end evidence must not reopen output.

The [Live API reference](https://ai.google.dev/api/live#BidiGenerateContentServerContent)
distinguishes model generation from model turn completion and places the last
output transcription before generation completion or interruption. Input text
has independent ordering, so this does not establish caller transcript finality.
Google's [pinned ADK receiver](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/models/gemini_llm_connection.py)
accumulates transcription fragments. The provider adapter therefore owns bounded
output-fragment assembly into the shared channel's cumulative snapshots, including
text received before engine admission. It must not concatenate in the engine or
publish generated text as a remotely heard prefix.

Only `outputTranscription` is the selected spoken-text source. `modelTurn` text
parts are not audio transcription and cannot be appended or used as fallback.
This also prevents thought text from being published as spoken output.

Earlier local playback must not move the resumption boundary earlier. Track
model-turn completion separately and require it along with idle caller/output,
settled playback, no pending tools and a valid private handle. Model completion
invalidates a previously received handle; a newer checkpoint is required. If a
new caller/typed turn starts before the previous model end, this allocation
remains non-resumable: an unqualified end cannot disambiguate ownership, and a
later handle cannot clear that uncertainty. Connection loss then fails explicitly;
renewal remains bounded by its existing deadline. This conservative interim
guard does not complete the separately required overlap-correlation support.

Retain existing PCM/credit bounds, cap assembled text at the shared 65,536-byte
bound, and erase retained text on settlement/fencing. An overflow fails the
allocation; no silent truncation, transcript fallback or history replay.

## Rejected alternatives and limits

- Growing pre-admission queues hides the incorrect admission boundary.
- Admitting on transcription fabricates activity and couples response control to
  transcript timing.
- Treating model turn end as caller end delays streamed audio and confuses IDs.
- Replacing each transcription fragment discards earlier words.

Sequential streaming proof is a dependency, not complete conversation support.
Independent caller/response association across overlaps, late input transcription,
history reconciliation, external/hybrid control and safe resumption remain explicit
milestone tasks. Client activity messages require automatic detection disabled;
the local adapter now rejects hybrid configuration before startup, including
tampered private setup. Shared hybrid support for other providers is unchanged.
Provider mode accepts only raw server activity for routine turn control; external
mode disables automatic detection and sends one client start/end per logical
activity. Idle ends and duplicates are no-ops on both wire and engine admission.
External end does not promote partial input text to final. These local profile
checks do not validate the separate interruption command or history contract:
the current interrupt encoder still requires that explicit milestone repair.

## Verification

Use the fake Google transport through the real owned capability and sink. Never
call Session.admit_output from the controller fixture. Exercise early retained
text/audio, twenty normally credited chunks before model end, fragment assembly,
matching generation/playback settlement, duplicate boundaries, aggregate overflow,
and fresh text after a settled reply. Record red-green evidence in
`labnotes/20260922-1830-google-sts-controller.md`.

The controller, codec/session/output and shared transcript-settlement group now
passes 68 focused checks. Two controller cases cover retained text through local
and pre-admission server interruption; these prove local isolation, not provider
history reconciliation. One separate resumption regression first reproduced
socket retirement before model turn end and now verifies safe deferral with no
replayed audio or control messages. Three additional provider/typed/external cases
reproduce a delayed prior model end and prove it cannot authorize an ambiguous
handoff. Full milestone acceptance remains open.

The subsequent profile/idempotence checkpoint extends that group to 72 passing
checks, including private setup rejection before socket creation. Its red-green
and independent review evidence is in `labnotes/20260922-1855-google-sts-control.md`.

## Next correlation checkpoint (not implemented)

The pinned ADK receiver distinguishes Gemini 3.x input transcription from its
older-model accumulation path: it treats `interimInputTranscription` as provisional
and `inputTranscription` as final. Its [model predicate](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/utils/model_name_utils.py#L184)
includes the configured `gemini-3.8-live` name. This is primary implementation
evidence for a model-specific codec profile, not a hosted trace. Do not generalize
the older optional `finished` field to this model or infer input finality from
model completion. Output fragment assembly remains separate.

The current local adapter still treats every input transcription as partial and
ties it to one mutable caller reference. The next checkpoint must keep pending
caller-final associations independently of output settlement, preserve existing
room attribution/policy boundaries, and prove late finals across caller onset.
The interim conservative resumption latch stays until response ownership is
actually established. Model interaction status and typed-input profile also need
verification before claiming complete Google conversation support; neither a
placeholder request nor history replay is authorized. Research and concrete tasks
are recorded in `labnotes/20260922-1903-google-sts-input.md` and the milestone.
