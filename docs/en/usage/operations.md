---
title: Operations and troubleshooting
description: Inspect calls, diagnose common failures and maintain credentials and catalogs.
sidebar:
  order: 11
---

## Establish what is working

`GET /healthz` returns `200 ok` when the HTTP handler is running. It does not query
PostgreSQL, validate provider credentials or establish media readiness. Check
login, a saved-resource read and an actual call separately after configuration
or deployment changes.

The tenant Calls directory shows **ongoing** or **ended**. Prepared calls count
as ongoing, so that label alone does not mean a caller joined. Open the call for
its pinned revision, timeline, transcripts, tool outcomes, variables and usage.

Inspection reads archived facts from PostgreSQL. An ongoing call may have newer
events than its persisted snapshot. `complete`, `incomplete` and `unconfirmed`
describe evidence, not a guess. Missing usage is not zero cost; a captured empty
tool result differs from a result that was not captured.

The conversation hides routine usage observations, playback progress/start/completion,
final transcription and turn-start/completion bookkeeping by default. Enable
**Technical events** in the conversation filters to inspect those records; this
works in both admin call details and the debug console. **Events** still controls
ordinary lifecycle activity, while **Logs** controls raw RTVI protocol events.
Messages, tool actions, failures and interruptions remain visible by default.
Filtering changes presentation only: archived evidence and Usage totals remain
intact. Large filtered conversations show 100 items per page.

Recordings and immutable call-detail publications are separate artifacts. They
require configured object storage and relevant capture permissions. A readable
inspection page does not imply a recording exists.

A recorded call offers a **Download recording** link on its call-details page,
serving one Matroska file (`recording.mka`) with a track per participant
connection plus a `room` track, all aligned to the same room-clock zero. Calls
without a recording show **Not recorded**, and calls whose spec requested a
recording the installation could not store show **Recording unavailable**.

## Inspect a guardrail failure

The published call-details JSON includes a private `decisions` section for calls with guardrail evidence. Find the evaluation by its source turn, candidate attempt or transfer invocation. Its outcome tells you whether the questions passed, a rule blocked the proposal, the provider returned an error, or the check was cancelled. A checker error can contain some scores and leave others unavailable.

For a blocked evaluation, match the question results by `evaluation_id` and read them in `ordinal` order. Each result records the question ID, required answer, threshold, P(Yes) when available, and the exact feedback line for a failed question. A separate dispatch receipt identifies the lines the model received. The transcript and delivery events show which response reached the caller. When storage permission was denied or unknown, the private content has a `content_unavailable` reason. An older publication can lack Decisions evidence.

Count each evaluation once and each provider request by its physical attempt ID. A retried request can belong to the same evaluation. The repaired reply is a separate conversational model attempt. Decisions usage includes provider-reported token counts when available. Keep inclusive total tokens separate from their input and output components.

## Passive latency diagnostics

Collection is off by default. In **Installation → Diagnostics**, built-in Admin
and Superadmin browser users can save **Benchmark using Silero VAD**. This is a
separate setting from a call's operational VAD switch. Tenant membership, custom
roles, API keys and call join credentials do not grant permission to change it.
Existing tenant call-inspection permissions govern reading collected reports.
Installation URL controls remain Superadmin-only.

The persisted value is read when each new call starts. Existing calls keep that
choice until they end. On a failed or conflicting save, reload the setting before
retrying. Changing the setting does not delete earlier reports.

The browser acceptance calls verified both room-service and operational Silero
with Scribe. The reported durations and resource costs are informational.
[Verification evidence](https://github.com/HashNuke/notes/blob/main/vxpipe/labnotes/20261120-0423-vad-milestone-verification.md).

The first live acceptance profile is human ElevenLabs Scribe v2 Realtime input
over browser WebRTC with local Silero off and on. Offline fixtures do not establish
live support for other providers, models or transports. Automatic attachment
currently requires configured automatic Scribe v2 Realtime mode and validated
provider settings. Scribe may omit `commit_strategy` from its acknowledgement;
that omission is retained, while the configured mode is recorded separately. A
complete acknowledgement also remains supported. Other omissions, conflicting
values, unsupported models/providers and manual mode do not attach an observer.
Provider `vad` commit strategy is independent of local operational Silero, which
can be off or on.

### Which audio is observed

Each supported, accepted human STT input is independent. When it already uses local
operational Silero, diagnostics reuses its evidence without a second inference
pass. Otherwise a room-owned passive Silero observer supplies the evidence.
Provider-side VAD and turn markers are separate signals. Diagnostics does not
commit STT, choose when a conversational turn ends, or change the operational VAD
setting.

Two humans using STT have separate detector states. A human STT input remains
eligible when it also controls a speech-to-speech agent, but native
speech-to-speech-only input has no STT source to observe. Agent output and mixed
room audio are never diagnostic sources. A response-agent transfer preserves
observation only when the accepted source and STT allocation survive; a real
replacement starts a new observation.

### Read the timing evidence

Open the **Metrics** tab in call details or the debug view. Each observed human
has a **VAD** row below their STT row, with **EOT** (end-of-turn detection) and
**Barge-in** (barge-in stop delay) columns. Collapsed, a cell shows the median,
p95 and how many turns or interruptions had a valid value. Expand the row for one
value per human turn; a missing value shows its reason. Select a value for that
turn's landmarks, source/clock identity, uncertainty, acoustic segments and any
interrupted output. Several speech segments can belong to one conversational turn.

The info icon next to **VAD** opens the observation: its source, profile and
coverage, and **Speech outside recorded turns**, which lists unmatched segments
without inventing turns or response samples. **Participant VAD** means the
participant's own Silero produced the evidence; **Room VAD** means the room ran
Silero because the participant had none. Different sources or profiles for one
participant get separate VAD rows and are never pooled. Omitted-segment counts
indicate bounded evidence loss. A row reads at most four pages of turns and says
so when more exist.

| Display | Meaning |
| --- | --- |
| End-of-turn detection | Estimated acoustic speech end to receipt of the STT signal that completes the human turn. Includes silence detection, buffering and network time; an interim transcript alone is not this endpoint. |
| Barge-in stop delay | Estimated human speech onset during agent playback to the matching server playback-stop acknowledgement. Cancellation dispatch and provider cancellation completion are not the stop endpoint. |
| Dispatch | STT turn-end receipt to the room accepting the completed input turn. |
| Response text | Room input completion to the first matching published response text. This need not be the model's first token. |
| Audio start | First response text to acknowledged server audio egress. This does not prove playback at the caller's device or remote hearing. |
| Observer confirmation | Delay between the estimated acoustic end and the detector confirming that end. |

End-of-turn detection and barge-in stop delay are the primary measurements.
Dispatch, response text and audio start are supporting breakdowns. For a barge-in,
the interrupted output can belong to an earlier turn or an answer to another
human; select the value to inspect that output and participant identity. This
measurement uses the TTS playback acknowledgement. It does not measure native
speech-to-speech playback, and it cannot prove that the listener's device has
finished playing already-buffered audio.

A turn can appear with incomplete evidence before STT completes. Barge-in duration
stays unavailable until its source interval and a unique acoustic onset are proven.
Late detector confirmation revises the same record using the original onset
estimate. Ambiguous onset, missing playback acknowledgement or an unstarted output
never becomes a zero-duration sample.

Values display in `ms`; landmark offsets share one observation's clock origin.
Do not subtract offsets across observations. Missing stages are unavailable, not
zero. Tool-only or silent responses can have no text/audio stages. Local Silero
resets at provider settlement can leave an incomplete endpoint; diagnostics does
not fill that gap with provider markers or a second detector.

VAD summaries show median, p95 and valid counts for one participant and profile.
Unavailable values do not enter percentiles. Check the source, coverage and valid
counts before comparing results.

### Coverage, troubleshooting and retention

Coverage describes the selected observation window, not the whole call or the
accuracy of its detector. `collecting` has a fresh heartbeat; `complete` means a
closed window has no recorded coverage loss. `incomplete` reports known loss.
`unconfirmed` means current completeness cannot be established, for example a
stale heartbeat after a writer crash or uncertain clocks. No observation means
not collected; it does not prove a zero-latency call.

| Symptom | Check |
| --- | --- |
| No observations | Saved collection setting, human STT eligibility, supported/acknowledged provider profile, source permissions and diagnostic service availability. The setting is read at call start; enabling later affects subsequent calls. |
| Partial start or source changed | Collection began late, an STT/source allocation changed, or input continuity could not be proved. Compare separate observations without stitching their clocks. |
| Observer unavailable or overloaded | Model readiness, bounded source/inference capacity and dropped-frame counts. Keep ordinary call behavior separate from diagnostic health. |
| Lease expired | The source attachment expired, or a historical record used the retired settings lease. Current calls retain their initial setting; an unavailable initial settings read leaves that call disabled. |
| Pending or missing stored turns | Allow the bounded writer drain, then refresh. A storage failure can lose diagnostics while the call continues normally. |
| Stale heartbeat | Refresh the report and inspect diagnostic writer/service health. Do not reinterpret an unclosed running record as a complete observation. |

Persisted diagnostics contain timing, identities, observation profiles, segment
boundaries and loss counters, not raw PCM or transcript text. They are still
call-associated metadata: use the existing authorized call-inspection path and
avoid copying caller information into logs. Turning collection off preserves
existing evidence. Deleting the owning call cascades to its diagnostic runs and
turn records; this feature adds no independent retention schedule. Call recordings
and transcripts retain their own storage and access rules.

See [runtime ownership and verification](../development/speech-runtime.md#passive-latency-observation)
for implementation boundaries and test lanes.

## Common failures

| Symptom | Check |
| --- | --- |
| Startup rejects configuration | Variable names in the error, selected database alias, keyring JSON and key length, `APP_HOST`, signing secret length. Do not log secret values. |
| Credential save fails | Encryption keyring availability, tenant/write permission, required provider fields and database connectivity. |
| Credential test succeeds but call fails | Save the credential, select the intended binding/model, and check provider quota/capabilities. A credential probe is not call acceptance. |
| Call will not prepare | Published revision, route, selected credentials, MCP catalog/configuration generations and variable validation. |
| Browser joins but is silent | Microphone permission, chosen devices, ICE/media reachability, actual media connection, STT/TTS/model errors and output policy. HTTPS signaling alone is insufficient. |
| Phone call never arrives | Carrier number/application association, exact scoped webhook URL, verification credentials, published number route and public HTTPS. |
| Phone call connects without audio | WSS upgrade support, carrier media stream, codec negotiation and permission/readiness failures. |
| Transfer stalls | Allowed destination, destination readiness/acceptance, originating service, timeout and wait/cue completion. Inspect failure recovery before retrying. |
| Tool unavailable | Explicit selection, schema pin, participant authority, current connection status and supported model/session operations. |
| Tool times out after submission | Treat the external result as potentially unknown. Check the external system before repeating a mutation. |
| Catalog stale or reconnect required | Background job state, endpoint availability, current grant and authorization scopes. Refresh is not a substitute for new consent. |
| Object download fails | Exact call/artifact ownership, bucket configuration, object availability and storage credentials. |

Use call IDs and bounded error codes when correlating logs. Avoid copying caller
data, raw transcripts, tokens, headers or credential envelopes into diagnostics.

## MCP catalog maintenance

Oban uses the application's PostgreSQL database. Its maintenance sweep selects
stale connected records; catalog workers open temporary sessions, discover all
pages and conditionally save a complete snapshot.

- `refreshed_at` advances only after a successful complete catalog publication,
  including a valid empty or unchanged catalog.
- `refresh_scheduled_at` advances only when a new job is committed.
- A recent scheduling timestamp suppresses duplicates for 30 minutes by default.
  A matching unfinished job also suppresses another enqueue after that window.
- Failed refreshes retain the last complete catalog and old freshness time.
  Replacement/disconnect prevents obsolete jobs from publishing results.

Inspect Oban's job/attempt state when work remains stale. Repeated authorization
failure needs reconnect; queue retries cannot grant missing access. Queue
concurrency is per node. Configure expiry/cadence in application settings, not
new environment variables.

## Rotate the installation encryption key

This changes encryption at rest, not the third-party API key:

1. Add the new key to every reader while retaining the old active write key.
2. Switch every writer to the new key ID, retaining both decrypt keys. Restart
   instances whose repository context captured the old keyring.
3. Drain operations that captured old key material, including in-flight OAuth
   renewal. Then run bounded batches from the trusted source host:

```shell
mix vxpipe.provider_credential.reencrypt --batch-size 100
mix vxpipe.mcp_credential.reencrypt --batch-size 100
mix vxpipe.mcp_oauth.prune --batch-size 100
```

4. Repeat until provider and MCP stores have no old-key rows. Inspect the prune
   command's `pending_by_key`; retain old keys until pending OAuth attempts are
   claimed or expired and removed. A zero count from one store is insufficient.
5. Remove the old key only after all writers/operations have switched, then
   restart and verify credential reads with the new key alone.

Re-encryption includes revoked rows and preserves identity/version/status. A
failed batch commits no partial replacement. Never change bytes under an existing
key ID. Packaged equivalents of these Mix commands remain delivery work.

## Backup, restart and retention

Back up PostgreSQL, object storage and the keyring through their respective host
mechanisms. Keep the keyring recoverable separately from database backups. A
restore drill must verify decryption and artifact access as well as table recovery.
There is no packaged automated backup/restore procedure yet.

Live room state and provider sessions are not durable. Drain calls before planned
replacement; a database backup cannot restore an interrupted audio conversation.
Durable cancellation/terminal evidence prevents cleanup from pretending that an
unknown outcome completed successfully.

Whole-call retention/deletion is still an unfinished milestone. Oban job-history
pruning is not call-data retention. Do not assume old calls, recordings or OAuth
attempts are all removed by the catalog maintenance sweep.
