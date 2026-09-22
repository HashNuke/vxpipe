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

## Caller correlation checkpoint

The pinned ADK receiver distinguishes Gemini 3.x input transcription from its
older-model accumulation path: it treats `inputTranscription` as a single final.
The Live server-content reference separately defines `interimInputTranscription`
as provisional; the inspected ADK receiver does not handle that field. Its [model predicate](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/utils/model_name_utils.py)
includes the configured `gemini-3.8-live` name. This is primary implementation
evidence for a model-specific codec profile, not a hosted trace. Do not generalize
the older optional `finished` field to this model or infer input finality from
model completion. Output fragment assembly remains separate.

The local adapter now separates interim/final input and retains its caller-final
association independently of output settlement, preserving the existing room
attribution/policy boundaries. Late finals across a competing caller onset remain
unproven and cannot be assigned by guesswork.
The interim conservative resumption latch stays until response ownership is
actually established. Model interaction status and typed-input profile also need
verification before claiming complete Google conversation support; neither a
placeholder request nor history replay is authorized. Research and concrete tasks
are recorded in `labnotes/20260922-1903-google-sts-input.md` and the milestone.

Design review found no primary-source premise for FIFO attribution across several
unfinished callers. A delayed A final after B onset is indistinguishable from a B
final before B activity end while A remains missing. The first caller checkpoint
therefore retains one unfinished audio-caller record independently of output and
typed input, retiring it only after final text and activity end. A new audio onset
that would compete with an unfinished caller fails the allocation explicitly;
no timeout/drop/queue shift is allowed. Model interruption cannot retire this
caller evidence. Unfinished evidence also forbids idle resumption.

This is an interim unambiguous profile, not successful overlap support or a change
to the required milestone outcome. It relies on the pinned model's single-final
premise; arbitrary cross-turn duplicate finals cannot be distinguished from the
next caller repeating the same words without upstream identity. Unassociated
input text cannot create a caller or be saved for a future onset. Stronger
correlation evidence and full response-ownership work remain prerequisites for
hosted advertisement.

Local verification: 95 focused Google codec/session/output, actual-controller,
shared-settlement and room transcript-mode tests pass. Twenty sequential actual-
controller replies retire all caller slots; finals before/after activity end and
after playback retain the original identity. A real room publishes a post-playback
final using its original public caller IDs. That room fixture replaces only the
prepared private runtime before source attachment; it does not bypass or claim
production-selection acceptance. Google remains absent from the manifest.

Review repairs retain the unfinished caller's response-admission anchor through
model interruption, so a genuine later caller end can stream and settle a fresh
reply. Renewal accepts an existing external caller's end instead of blocking the
evidence needed to reach idle. A real caller end requires subsequent model-end
evidence before renewal; an earlier interrupted model end cannot mark the fresh
reply complete. General overlapping model-response ownership is still separate.
If that interrupted-model end has not arrived when the caller ends, ownership of
a subsequent model end remains ambiguous. Latch the allocation as non-resumable;
later ends and handles cannot restore certainty. The reversed-order controller
regression and combined recognition/startup/room group pass 229 tests locally.
