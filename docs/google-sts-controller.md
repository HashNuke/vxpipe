# Google STS controller boundaries

Status: sequential controller and configured Google selection are implemented.
See [Gemini provider acceptance](milestones/gemini-live-provider-acceptance.md)
for real-provider evidence. Fake-wire acceptance is not hosted interoperability
or interruption-history proof.

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
invalidates earlier idle evidence; the latest non-revoked session token is retained. If a
new caller/typed turn starts before the previous model end, an unqualified end
cannot disambiguate ownership, and a later handle cannot clear that uncertainty.
A subsequent genuinely new, attributable exchange at a settled idle boundary
can repair it after fresh model content, caller completion and settled output.
Omitted status on a completed turn is sufficient only for same-allocation rotation;
new input origins still need explicit idle.
Pending rotation keeps accepting input; only the actual switch holds its one
unsent ordered command. Connection loss without a safe checkpoint still fails.
See [the lifecycle decision](gemini-live-session-lifecycle.md). These guards do
not complete separately required overlap-correlation support.

Retain existing PCM/credit bounds, cap assembled text at the shared 65,536-byte
bound, and erase retained text on settlement/fencing. At the sixteen-chunk queue
limit, compact pending PCM within its exact response into chunks of at most
131,072 bytes. This preserves order, response identity and the existing byte
budget while accepting bursts of small wire packets. It never combines audio
across responses or touches the outstanding channel credit. A full byte budget
still fails the allocation; no silent truncation, transcript fallback or replay.

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
External end does not promote partial input text to final. The separate
engine-requested interruption and provider-history limits are below.

## Engine-requested and server-reported interruption

The [Live WebSocket reference](https://ai.google.dev/api/live) restricts client
`activityStart`/`activityEnd` to sessions with automatic activity detection
disabled, and defines `activityEnd` as the end of **user** activity. The
[capabilities guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
describes interruption through real user activity, with `interrupted` reported
by the server. This inspected profile has no history-neutral standalone
response-cancel command. Sending `activityEnd` in provider mode was invalid;
sending an idle end in external mode would not cancel output. Synthetic caller
activity or client content would modify conversational history, so neither is
an acceptable replacement.

An unrelated manual interruption of the current Google wire response therefore
returns a failure and terminates that allocation. When Google has already
reported genuine caller onset, room-owned barge-in instead discards the current
response locally and waits for the actual server interruption/model boundary.
It sends no synthetic activity or standalone cancel and preserves the allocation. It does not claim successful
same-socket barge-in or truncated provider history. A local discard of an older
response already off the wire remains response-specific and does not interrupt
the newer wire generation. By contrast, a genuine server `interrupted` event
fences local output without echoing another client interrupt; the exact shared
output slot retires after its outstanding audio credit and terminal event.
An old legacy output grant arriving after its interrupted turn has retired fails
the allocation instead of silently occupying the channel slot.
If a genuine B caller starts after A's model boundary while A's local PCM
credit is still pending, legacy adapter state retains B's bounded text, PCM
and generation completion separately from A. B is published only after A's
credit/terminal settles and the engine grants B's own output reference. This
also holds when A's terminal already exists but its settlement is delayed:
settling A does not erase B's buffered transcript. Until A's model boundary,
the local fence drops unlabelled text, PCM and generation completion even if B
has begun speaking. This handling does not infer an origin for unlabelled wire
content without a distinguishing model/caller boundary.

Rejected alternatives: retaining the unsupported `activityEnd` encoder,
manufacturing `activityStart` or `clientContent` to provoke a barge-in, and
assuming sink interruption alone proves upstream history reconciliation. The
local fake-wire tests cover both VAD profiles, opted-in and legacy response
owners, credit ordering (including delayed A credit with B already generating),
stale grants, and next-reply isolation. They do not
prove hosted behavior or attribution of unlabelled content that could arrive
after a new caller begins; those remain open milestone gates.

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

**Superseded 2026-10-07 (call continuity).** Live Gemini calls ended with
`activity_start: ambiguous_input` when a caller turn received no input transcription (noise or a
cut-off word) and the next turn began. Failing the session ended the caller's phone call over
transcript bookkeeping. A new onset now settles the earlier caller with an empty final, marks
socket resumption ambiguous, and settles the new caller's first final empty as well, because it
may be the earlier caller's late final. Nothing is attributed by guesswork; at most one turn's
transcript is lost, and the room treats an empty final as settled evidence rather than caller
text. External turn control follows the same rule. The original rationale follows.

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
a subsequent model end remains ambiguous; later unqualified ends and handles
cannot restore certainty. The 2026-10-08 lifecycle repair allows a subsequent
clean attributable exchange to discharge that uncertainty. The reversed-order controller
regression and combined recognition/startup/room group pass 229 tests locally.

## Interaction and new-text profile

The pinned ADK sends genuinely new, single-part Gemini 3.x user text through
`send_realtime_input(text=...)`. Use raw `realtimeInput.text` for that operation.
Do not reuse the history-append envelope, replay a conversation, or copy the
ADK's separate placeholder-generation example. This changes new typed input,
not resumption or context reconstruction.

The same receiver exposes interaction status because one prompt can span several
model turns. The [pinned Python SDK](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/types.py)
defines `IDLE` and `IN_PROGRESS`, plus unspecified and deprecated
`REQUIRES_ACTION`. The field accompanies model completion. Decode a closed enum
with that completion; reject invalid types or an unaccompanied status. Missing
status becomes `:omitted`, distinct from explicit unspecified/unknown status; it
does not inherit earlier idle for origin cutover.

The local origin-cutover rule requires explicit `IDLE` after conversational
work as well as the existing model, caller, playback, tool and ambiguity fences.
Same-allocation rotation also accepts an omitted status on a genuinely completed
turn, matching the current hosted wire; explicit non-idle status still defers it.
Unspecified and deprecated status do not grant renewal. Treating deprecated
`REQUIRES_ACTION` conservatively is this adapter's decision, not a claim that the
SDK calls it active reasoning. New caller/typed work and accepted tool results
invalidate the previous idle evidence. A valid new handle alone cannot restore
it. A pristine setup with no conversational work may still use its first handle;
there is no old response to settle. No resumption deadline is extended.

Verification uses exact codec payloads and the actual capability with a fake wire:
one new typed input yields one normally credited reply; a completed exchange with
omitted status can rotate with the latest valid token, while explicit unspecified,
in-progress and deprecated status defer it. Delivering a tool result after idle
requires fresh model/completion evidence. Keep late caller-final and pending-playback
guards intact; omitted status still cannot authorize a new input origin.

Review extends invalidation to accepted PCM before provider onset without
inventing model/caller onset or an overlap latch. A private model-activity marker
also covers thought-only `modelTurn` parts; output transcription and tool calls
invalidate idle before any ownership-based drop. Thought text is never published
as spoken text. Explicit `turnComplete: false` alone produces no completion;
status still requires a true completion envelope.

This profile repair does not complete continued response delivery. A second model
response after `IN_PROGRESS` currently lacks an independent response association
once the first output settles. That needs a separate bounded response owner and
engine admission, not a fabricated caller end or a longer buffer. The milestone
keeps that successful multi-response requirement open along with overlap and
interruption-history acceptance. Red evidence is in
`labnotes/20260922-1946-google-interaction-profile.md`.

The same status guard must cover standalone generation/interruption notifications,
with any explicit idle completion in the same envelope applied after observing
activity. A separate [checkpoint-coverage audit](sts-context-restoration.md#implemented-handle-handoff)
remains open: idle and handle arrival do not account for the provider's consumed-
client-message watermark or prove cross-direction no-loss handoff.

## Source PCM and physical phone playback

Native phone sinks pad a final PCM packet to 20 ms. Provider output settlement
counts generated source samples; it must exclude that silence padding while
retaining physical completion as the publication fence and transport estimate.
The capability converts a sink duration within the final packet bound to at
most the accepted source duration. An impossible larger report still fails
settlement. Partial-frame and excessive-report regressions cover this distinction.

Sink pushes run in the capability tree's owned task supervisor. The capability
retains the exact pending audio credit until the task succeeds, so only one
push is in progress while caller input, policy changes and interruption remain
responsive. A fenced task's completion releases its original credit and cannot
revive old output or transcript. Local contract tests exercise a blocked sink;
shared settlement tests cover 8, 16, 24 and 48 kHz without a live account.
