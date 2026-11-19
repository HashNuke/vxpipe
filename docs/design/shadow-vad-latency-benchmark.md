# Passive speech-end latency benchmark

Status: researched design, not implemented. 2026-11-19. Implementation tasks live
in [Passive call latency diagnostics and readable timelines](../../labnotes/milestones/passive-call-latency-diagnostics.md).

## Decision

Measure estimated acoustic speech end against receipt of the provider evidence
that actually ends the turn using an optional diagnostic observer. Committed
transcript receipt is a separate landmark, not a synonym for turn end. Reuse the pinned Silero model
and PCM conversion primitives, but not the existing conversational `vad` switch.
Persist per-turn summaries in separate call-owned diagnostic tables, outside the
ordinary call timeline; expose a collapsed authorized Latency diagnostics view.

This estimates speech end in the audio received by Vxpipe. It does not establish
the physical microphone endpoint or isolate provider compute from network delay.
Silero is a reproducible acoustic baseline, not human-labelled ground truth.

## Existing implementation evidence

- `Speech.Silero` consumes 16 kHz mono PCM in 512-sample windows (32 ms), with
  independent recurrent state. `Silero.Model` loads the pinned v6.2.3 ONNX asset.
- `Speech.ActivityBoundary` confirms onset after four frames above 0.5 and end
  after sixteen frames below 0.35. End confirmation takes 512 ms of silence; the
  returned sample position is backdated to the start of that silence.
- `Speech.ConversationalSTT` uses local onset to call
  `STTTurnStart.activity_started/1`; it ignores the acoustic end position.
  Detector readiness, buffer limits and failures affect the STT session. It
  resets detector state on provider turn settlement, which is unsuitable for
  delayed independent measurement of the same endpoint.
- `Speech.ActivityRuntime.submit/3` is a synchronous admission call (up to five
  seconds), although inference runs in supervised tasks. It must not be invoked
  from the live media path for optional benchmarking.
- `Media.AudioFrame` already carries media timestamps, sequence numbers,
  `received_at`, connection/participant identity and source epoch.
  `STTActivityPCM` normalizes PCM and its sample timestamp to 16 kHz; the current
  conversational wrapper discards that normalized timestamp.
- `ElevenLabs.ScribeSocket.handle_frame/2` decodes then forwards provider events.
  Add a monotonic receipt timestamp at the earliest application socket boundary,
  before owner mailbox processing, and carry it through diagnostic correlation.
  The existing room `participant_turn_completed` event timestamps later handling.
  Crucially, continuous Scribe accumulates committed segments and settles only
  on an empty provider partial after committed text with no outstanding draft.
  Timestamp that exact end-evidence receipt separately from text commits.
- Both historical manual-commit Scribe and provider-VAD Scribe paths exist.
  Record the effective strategy, model and acknowledged settings per session;
  do not infer them from a missing source-spec option or a current default.

## Measurement contract

For each participant, connection, source epoch and correlated provider turn retain:

1. Estimated last-speech boundary as a media sample offset, plus its mapped
   server monotonic time and mapping uncertainty.
2. Time the observer confirmed that boundary and its inference/queue lag.
3. Provider text-commit receipt, actual turn-end-evidence receipt and adapter
   turn-end emission time.
4. Room turn-completion time, allowing internal scheduling latency to be split
   from provider receipt latency.
5. Explicit manual-commit send time when applicable.

Primary metric: `provider_end_evidence_received - estimated_acoustic_end`.
Separately report `observer_confirmed - estimated_acoustic_end` and
`room_turn_completed - provider_end_evidence_received`.
For manual commit, split acoustic-end-to-commit from commit-to-final-receipt.
These intervals include application transport and network work; they are not
pure STT inference durations.

Do not subtract the observer's confirmation time: that would hide its 512 ms
silence window. Do not mix media sample offsets with UTC timestamps or assume
packet arrival equals microphone capture. Validate the `received_at` clock/unit
for each transport; preserve a per-epoch sample-to-monotonic mapping and expose
jitter/discontinuity uncertainty. No single call-start offset is sufficient when
media gaps, loss or source changes occur.

Maintain a continuous standalone observer stream independently of provider turn
resets. When reusing operational inference, preserve its resets and mark affected
coverage incomplete rather than altering call behavior.
Match the final relevant acoustic segment to each committed turn, allowing
multiple pauses, provider segment commits, overlaps and late observer results.
If correlation is ambiguous, audio is missing, or speech resumes during a
candidate gap, mark the sample ambiguous/incomplete instead of manufacturing a
latency. Report excluded counts alongside p50/p95 and sample count.

## Isolation and rollout

Start with offline processing of an existing isolated participant recording if
it retains usable timing alignment. Availability and alignment of recordings for
the reported call have not been established; archive events alone cannot recover
its acoustic endpoint. Offline VAD needs the original provider receipt trace for
an exact historical comparison, which the current events do not supply. The
required trace distinguishes text-commit receipt from turn-end-evidence receipt.

For future live measurements, copy accepted caller audio to a bounded observer
queue. Never await inference, readiness, persistence or capacity from the live
call. A plain unbounded mailbox is not sufficient. On overflow drop benchmark
data, mark the interval invalid, and reset detector continuity. Do not block,
commit STT input, emit speech control events, interrupt an agent or fail a call.
Use separate supervision and inference capacity; cap CPU/memory and sampled
calls. A separate OS process offers stronger native-runtime failure isolation.
Any live observer has nonzero copy/CPU overhead; demonstrate bounded overhead
instead of promising literally zero interference. Persist timing summaries and
quality flags, not raw audio, by default.

## Rejected alternatives

- Enable existing `vad: true`: changes operational onset behavior and shares
  session readiness/failure handling.
- Use final-transcript/room-turn timestamps alone: excludes the unknown speech
  endpoint and conflates provider receipt with internal processing.
- Enable provider word timestamps as the sole baseline: not independent acoustic
  evidence; current protocol decoder does not support that event type.
- Add a second live STT request: unnecessary cost and a different network path.
- Treat all silence as turn end: conversational pauses are not completed turns.

## Required verification before implementation acceptance

- Red/green boundary tests for sample-time mapping, backdated endpoints, provider
  final arriving before VAD confirmation, resumed speech and multiple segments.
- Failure/overload tests demonstrating identical production turn decisions,
  provider input bytes and commit behavior with the observer on and off.
- Disconnect, source-epoch, packet-gap, observer crash and native timeout tests.
- Replay labelled caller-only audio, including noise/echo and agent overlap;
  quantify endpoint error rather than assuming 32 ms windows imply 32 ms accuracy.
- Controlled on/off load comparisons for CPU, memory, audio drops and response
  latency; small opt-in live trial with diagnostic summaries only.
- Repository completion checks for implementation; Lean lane if production speech
  state-machine behavior is changed. No runtime code changed in this research.

## External sources

- [Silero reference implementation](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py): sample-based endpoints, silence confirmation and padding.
- [ElevenLabs commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies): manual versus provider commit and optional word timestamps.
- [ElevenLabs event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference): committed transcript event semantics.

## Durable reports and display decision

The user approved separate durable diagnostics and later requested timeline cleanup.
Use one run/coverage record plus one revisioned logical row per human turn, with
clock provenance, bounded configuration, null unavailable milestones and quality
reasons. Keep loss/disabled/unsupported states distinct. Retry idempotently through
a separately bounded writer; tenant/incarnation checks and call deletion guard
late writes. Diagnostic availability never changes call/publication completeness.
The initial slice does not alter immutable details exports.

Default conversation/debug views hide usage observations, delivery progress/start/
completion, final recognizer transcript, participant turn start and agent turn
completion behind Technical events. Retain accounting and diagnostic records in
production. Messages, tools, failures and interruptions remain visible. Filtering
is by canonical kind, not labels or logger levels. The milestone owns detailed
query, lifecycle, migration, UI state and acceptance contracts.

## App-settings authority (user clarification)

Passive VAD benchmarking is installation-wide, default-off and enabled only by
the persisted **Installation → Diagnostics → Benchmark using Silero VAD** toggle. Built-in admin and superadmin
browser-session principals alone can change it, enforced on server routes and
domain operations. Keep the existing installation URL operation superadmin-only.
No environment, embedding, call-spec or view option can bypass a disabled setting.

Apply versioned settings to active and new eligible calls without synchronous
per-frame reads. Bound propagation and enabled-cache leases; unknown/expired
authority disables diagnostics without affecting calls. Enable starts a fresh
epoch (mid-turn evidence is incomplete); disable revokes capture and discards
queued audio, while already captured summaries may finish bounded persistence.
The UI distinguishes saved intent from applying/effective state. Existing reports
remain readable under ordinary inspection authorization. Re-enable never bridges
the unobserved interval. The milestone defines tasks and acceptance cases.

## Reuse existing operational inference (user clarification)

If a call already runs Silero, reuse its timestamped probability/sample evidence
through a bounded observer; do not execute the model twice for the same source
audio. Keep diagnostic state separate. Preserve operational admission, resets,
readiness and failure handling; missing evidence yields incomplete measurements,
not a hidden second inference pass. Mark this provenance as operational reuse,
not an independent detector comparison. If operational Silero is absent, run one
isolated benchmark-only stream while the setting is on. Turning it off detaches
only diagnostics and leaves any call-spec Silero running normally.

The toggle lives in a Diagnostics section of the existing Installation page.
Admins may access that section; the installation URL and its operation retain
their existing superadmin-only authorization. Implementation must replace the
whole-page guard with section-specific access and test both roles.

## Timing foundation decisions

The initial sample-clock implementation retains a bounded set of received audio
frames. A frame owns positions after its start through its endpoint; only the
first frame also owns its start. Eviction therefore expires a shared boundary
instead of reassigning it to a neighboring packet with a different receipt time.
Mapping subtracts remaining sample duration from packet receipt time and carries
receipt jitter as uncertainty. If compressed arrivals would make the inferred
sample timeline move backward, that frame is unavailable (`clock_uncertain`).
These are server-receipt estimates, not microphone capture timestamps.

Turn evidence uses one clock identity and bounded integer offsets. Missing stages
remain null, and an inverted causal chain invalidates affected stage durations.
Two distinct acoustic endpoints submitted to one unresolved turn are ambiguous;
the correlator must identify the final speech segment before assigning an endpoint.
It must not silently select the earliest pause. Invalid acoustic evidence does not
erase independently valid provider/adapter/response stages.

Neutral run and turn records reject arbitrary configuration and payload fields.
Turn durations are derived from allowlisted landmarks rather than accepted from
callers. This prevents a supplied latency value from contradicting its evidence;
it does not replace repository ownership, revision or lifecycle enforcement.

## Persistence admission and failure isolation

The diagnostic writer reserves a count and retained-payload byte allowance before
sending a non-suspending message. Validated strings are copied so small slices
cannot retain unexpectedly large backing binaries. The byte charge covers four
payload copies plus an envelope allowance; it does not claim to bound total VM or
database-driver heap usage. Queued, executing and retrying writes retain the same
reservation. Attempts and final draining have finite deadlines.

A linked helper keeps the writer responsive while the database task is admitted
through its dedicated Task.Supervisor. The deadline includes admission. Killing
the writer or helper also retires linked database work; a late admission cannot
invoke the repository for a dead helper. This avoids relying on terminate callbacks.

Task-supervisor startup itself uses an infinite call in the dependency. A separate
pool-owned gate therefore bounds unresolved startup requests across writer
lifetimes. A killed helper with unknown startup outcome retains its admission
permit until the whole diagnostics pool is restarted. Releasing that permit on
timeout would allow a suspended supervisor's mailbox to grow without bound.
This conservative degradation affects diagnostics only and must be exposed as
unavailable/incomplete coverage; it must never change call behavior or claim a
complete latency sample. The pool is not yet connected to runtime capture.

## Reproducible offline timing report

Run `bin/replay-latency-diagnostics` after `bin/setup`. It creates a uniquely named
local test database, applies migrations, and replays the existing synthetic speech
fixture through real Silero inference and the actual Scribe adapter using an
in-memory transport. It makes no provider network calls. The command prints the
database name and a `--read DATABASE` command for inspecting it again; fixture
databases are retained for this purpose. It requires local PostgreSQL and forces
the test database configuration rather than using a production database URL.

The complete scenario supplies a logical provider end 300 ms after the estimated
acoustic boundary. Observer confirmation occurs later and is stored separately.
The missing-audio scenario omits a frame: its acoustic delay is null, its coverage
is incomplete, and independently valid provider stages remain available. Both
reports are written through the bounded asynchronous writer and read in a new
BEAM process. No ordinary call facts or raw audio/transcript are stored by this
fixture. The output includes a JSON artifact in the system temporary directory.

These provider offsets are deliberately synthetic. The command verifies timing
semantics, correlation, persistence and restart reads; it does not measure live
Scribe latency or acoustic endpoint accuracy. The offline correlator supports one
identified source and clock, rejects resumed-speech ambiguity, and preserves gaps.
Live source replacement and output correlation remain checkpoint C work.

Coverage distinguishes collecting, complete selected windows, incomplete capture,
storage loss and unconfirmed runs. A stale running heartbeat after restart cannot
be presented as a graceful close. A complete run does not imply that the whole
call was observed: disabling and call termination remain separate end reasons.

## Settings authority implementation constraints

The Identity diagnostics-settings port is separate from installation URL operations.
Its domain accepts only built-in admin/superadmin browser-session principals and
strict boolean/revision inputs. The persistence adapter must revalidate the current
stored role and session on reads and writes; a principal's old role fields alone
are insufficient. It must atomically update the boolean, revision and attribution
with the audit event. A stale save conflicts, including a stale apparent no-op.
The absence of a configured port is unavailable, never an enabled default.

The Engine's local settings evidence has a fixed three-second lease measured from
the authoritative database read's start on that node's monotonic clock. Measuring
from response arrival would let a stalled pre-disable read extend enabled authority.
Equal revisions can refresh only from a later read; conflicting contents for an
equal revision fail closed until a higher revision arrives. Lower revisions and
reordered replies cannot overwrite newer authority. Clock mismatches and expired
leases cannot authorize capture. These pure contracts are tested; the projector
and live admission/processing checks are not yet connected.

Runtime integration must poll at most once per second with one bounded outstanding
read per node, check the lease both before admission and before queued work runs,
and discard queued capture on expiry/revocation. Invalidation messages can shorten
propagation but cannot grant authority or extend the lease. A disabled save must
remain visibly applying until acknowledgements or the lease bound establish that
previous grants have expired. Native inference already executing may outlive task
cancellation; its late result must be fenced from any new run. No claim of zero
overhead or instantaneous native cancellation follows from the three-second lease.

The durable implementation uses a dedicated `installation_diagnostics_settings`
singleton, keeping URL settings and their authorization unchanged. Migration
creates disabled revision zero. Positive revisions require updater public identity
and update time; the audit event and setting commit together. Missing singleton
rows are unavailable rather than implicitly recreated. Read/write operations lock
the current user, role and session, and recheck expiry after settings-lock waits
before returning data or changing the setting. The internal snapshot read is for
the future projection only; it does not provide a public unauthenticated endpoint.

## Local projection IO isolation

A dedicated reader process owns one settings-read slot. The projection starts it
asynchronously, polls no more often than once per second, and stops accepting a
result at the one-second deadline. Elapsed time is checked when a result arrives,
not only by a timer message. Timeout revokes authority but retains the slot until
the read actually settles; it does not start replacement work behind a blocked
dependency. This trades temporary diagnostic unavailability for bounded work.

Consumers read a small protected ETS projection and evaluate the three-second
lease against the current local monotonic clock. They never wait for the reader
or projection process. An invalidation hint is coalesced before messaging and
fences the outstanding result when processed; it cannot grant authority. The
reader/projection supervisor shares lifecycle and is temporary at its parent
boundary. Exhausted retries therefore leave diagnostics unavailable rather than
forcing the containing application's unrelated children to restart.

Database-backed application startup now injects the Persistence snapshot loader
into this pool. The Engine owns no database dependency and startup does not await
the first read; a not-yet-started Repo leaves diagnostics unavailable until a
later refresh succeeds. This composition is not an alternate enable authority.
Actual snapshot-port tests cover durable off/on/off revisions. Cross-node hints,
consumer revocation/queue fencing and UI propagation status remain required
before claiming configured-call capture.

## Capture admission and authority continuity

An enabled saved revision is accompanied by a local publication epoch and finite
lease deadline. Refreshing a still-valid snapshot preserves its epoch. Observed
expiry, failed reads, invalidation, projector restart or a different revision
retires it. Readers irreversibly poison an observed-expired epoch so a delayed
publication cannot restore it. The epoch alone is not a continuity guarantee:
each handoff independently retains its last validated lease deadline and can
renew only when its next sampled authority check precedes that deadline. A late
publication therefore cannot revive queued work on an expired handoff, even if
no reader observed the old projection's expiry. An idle consumer that fails to
renew within its lease must start fresh; a worker should check during its bounded
lifecycle tick as well as before inference/results. Pending invalidation denies
new grants before projector processing.

Checks linearize at their monotonic clock sample, not the wall-clock instant a
preempted function returns. A concurrent observed expiry irreversibly closes the
handoff; renewal never clears that close. Consumer deadline extension uses one
compare/exchange attempt, never a blocking lock or retry loop. A check delayed
across its sampled prior deadline may conservatively retire the handoff even
when another check renewed it meanwhile; restart with partial coverage rather
than preserve uncertain continuity. Producers and
consumers recheck at delivery, processing and result acceptance boundaries.

The separate capture handoff defaults to64pending items and262144charged bytes,
including admitted work still processing. Hard configurable maxima are128items
and8388608bytes. Charge includes two serialized payload copies plus512bytes of
envelope allowance. A bounded reservation precedes detached binary copies and
non-suspending send; saturation drops evidence and increments loss counters.
Allowed transient packets are linear16 audio frames, bounded probability batches
with inference epoch/sample cursor, and fixed reset notices. Text and unrestricted
provider metadata are excluded. These packets are not ordinary archive events.

This is a handoff primitive, not the complete observer lifecycle. Its consumer
must own exactly-once release, check the same grant before processing and accepting
results, discard queued audio on revocation, and report loss/partial coverage.
Source identity/privacy checks, worker admission, native inference isolation and
bounded shutdown remain required for live capture. None of these APIs override
the durable app setting or initialize a model on their own.

### Accepted-input observation boundary

A diagnostic audio tap attaches to a ready STT capability's exact native allocation,
installed media-policy revision and transport track/source epoch. Private/prepared
allocations and unknown policy cannot grant observation. The tap runs only after
normal provider input admission succeeds, so diagnostic work cannot broaden the
source inputs already permitted by the call's media policy. This is transient
observation, not an audio recording or a change to recording/transcript settings.

Handoffs carry an owning capability PID as well as their receiving consumer PID;
receipt checks fail when either dies. A successful policy installation closes the old handle before acknowledgment;
native allocation retirement closes it before teardown. A source mismatch closes
it before any diagnostic copy. Old queued evidence cannot cross those transitions.
Rejected policy commands preserve the active tap, and prepared replacements do
not inherit it. The binding uses the global installed policy revision, not the
source STT interval. Exact repeat attachment is idempotent;
a different source/allocation needs a fresh handle. The current hook accepts raw
PCM only; decoded-Opus mapping and automatic observer lifecycle remain pending.

### Operational inference observation

ConversationalSTT may receive a prospective diagnostic handoff for its exact native
allocation and live channel consumer owner. Subscription requests pass through
the channel asynchronously, including after prepared-allocation adoption. It tags an existing inference submission with that
handoff, operational recognition epoch and first 16kHz model-window sample cursor.
Completed probabilities are mirrored before existing stale-epoch suppression;
no second model execution or recurrent state is created. Warmup is excluded.
Source identity is fenced before provider admission starts, so reused inference
cannot publish replacement-source probabilities into the old handoff while audio
admission is still awaiting a reply. Provider settlement and failure emit bounded
reset notices without changing the
operational reset/failure path. Late results retain their original epoch.

A mid-stream subscription with already processed, pending, odd-byte or in-flight input is
partial and does not adopt that input. It waits for the next operational reset to
mirror a fresh epoch. An operationally retained odd byte keeps the next epoch
partial as well; diagnostics never change that retention. Per-epoch model cursors are not transport timestamps: the
future run consumer must associate them with accepted-source mapping and report
incomplete evidence when that association is absent or crosses a reset. This
hook does not supply independent inference when call-spec VAD is off.

### Standalone inference admission foundation

A diagnostic ActivityRuntime instance may expose an explicitly configured
`diagnostic_capacity` (1–32); ordinary operational instances do not expose this
handle. `InferenceAdmission` reserves a slot before copying or sending, so a
suspended runtime cannot accumulate more than its configured number of offers.
Each offer permits at most 32,000 PCM bytes and 16,384 serialized stream bytes.
BEAM binary views are detached; native tensors retain the pinned model's fixed
shapes. Serialized sizes do not measure opaque native allocations.

Queued and running requests share the reservation. Busy execution rejects rather
than adding another queue. Result delivery does not free capacity until the task
terminates. Unknown reservations after producer death conservatively consume
capacity until runtime restart. This may degrade diagnostic availability and must
be reported as missing coverage; it does not justify reclaiming uncertain slots.

Capture authority is checked before enqueue, admission, model load, classification
and delivery. Active diagnostic jobs check revocation every 250 ms, in addition
to the existing load/inference deadlines. Native work keeps its execution slot
until actual termination. This asynchronous API is a foundation for the isolated
source workers; production composition and automatic call attachment remain open.

### Accepted-audio timeline foundation

`AudioTimeline` projects already accepted PCM into the same 16 kHz normalization
used by operational activity detection. A decoded Opus copy is eligible only when
its timestamp, sample rate and mono channel metadata match the accepted transport
frame exactly. Capture delivers just that PCM and bounded identity metadata,
without changing provider input. Raw Opus without a decoded copy still needs an
isolated decoder path before the supported-live profile is complete.

Continuity is checked on original transport samples before normalization, so a
missing source sample cannot disappear through rounding. A gap drops the prior
mapping; changed source/participant/connection/rate and reordered evidence are
rejected. Identical admitted duplicates do not cause duplicate inference, while
conflicting duplicate PCM fails validation. Consumers must reset their observer
stream on gaps or rejected evidence rather than bridge the missing interval.

Receipt timestamps are converted from milliseconds to integer microseconds
relative to the run origin. Normalized mapping history is bounded (256 frames by
default); expired or unobserved positions stay unavailable. Uncertainty includes
receipt-clock jitter plus a conservative source/output sample-period allowance.
This is server receipt mapping, not microphone capture time. Automatic source
worker composition and end-to-end transport acceptance remain pending.

### Benchmark-only source worker

`SourceWorker` composes accepted-audio mapping with sequential async inference and
its own acoustic boundary state. A coordinator supplies a source/run-specific
output handoff and matching capture owner/grant; the worker emits only fixed,
bounded acoustic boundary tuples and provider landmarks. The output handoff must
not be reused across source/run associations. First-turn coverage remains partial
through the first completed endpoint. Missing or uncertain mappings have null
positions, not fabricated durations. Provider settlement leaves this standalone
recurrence untouched; source gaps and inference failures advance its diagnostic
epoch and reset only its private detector.

Queued input and the active inference packet keep capture reservations until
processed or discarded. Output saturation stops the worker. Owner, collector or
runtime death and250ms authority checks retire it; runtime owner monitoring
cancels its model job and keeps native capacity until actual termination. Graceful
supervised shutdown discards queued audio and releases its reservations. Hard
process death still fences offers and frees queued payloads without relying on
`terminate/2`; an interrupted producer can conservatively leave old-handle counters
occupied, so counters are not a guaranteed durable loss ledger.

`SourceSupervisor` is a separate temporary diagnostic subtree, with16 sources and
one model task by default (maximum32 sources/eight tasks). Its pinned model loads
lazily in its own runtime, not through operational model-cache initialization.
Lifecycle startup is coordinator-only and must not be invoked on the voice path.
This composition has fixture acceptance but is not automatically attached to
configured calls yet. Reused-inference consumption, collector correlation,
production attachment and the full operational/benchmark on/off matrix remain open.


## Automatic source attachment runtime

The optional isolated source pool owns a node-local coordinator alongside its
workers and inference runtime, under the same one-for-all supervision boundary.
A coordinator crash retires that pool before a replacement starts. Workers also
monitor their coordinator; none of these processes owns the operational speech
allocation. The application must supply a collector factory before installing this
coordinator. Production wiring waits for the live collector and configured-call
acceptance; merely adding these modules does not enable capture.

The coordinator walks room registry identities and asks one room for a bounded
page of current human STT sources. It retains only room/connection cursors, at most
one pending discovery, and at most16 active sources by default (configuration cap32).
The default poll is250ms. Discovery uses the next provider-accepted frame and
expires at the capability after250ms; the coordinator abandons missing replies
after500ms and checks that deadline again when a reply arrives. Discovery and
attachment RPCs use250ms budgets. The capability retains a one-use source proof
for at most5s, invalidated by a subsequent accepted source change, policy change,
allocation retirement or settings revocation. Attachment consumes this proof;
a room snapshot alone cannot prove that a transport epoch stayed unchanged. The room and discovered policy/allocation/source are rechecked before
attachment, including after collector startup. One active source is revalidated
per enabled scan in round-robin order even when capacity is full; therefore a
complete active audit takes at most the configured source count in scan steps.
Operational source/policy fencing remains immediate at accepted audio; this audit
also retires disappeared room/agent bindings. Revalidation queries the exact
connection, so movement between discovery pages does not retire a healthy source.
Unsupported, private, held and
native speech-to-speech contexts do not grant
a source. There is no pilot allowlist. Room selection uses a transient Registry
identity snapshot, whose allocation scales with current registered rooms; the
load gate must measure this cost rather than claiming constant-memory enumeration.
No list of pending room work is retained.

Collector creation, source-worker startup and capability attachment run only in
the coordinator, never in a room/audio callback. The injected collector factory
receives bounded call/source identity, run/clock origin, mode and coordinator PID
and returns a bounded CaptureHandoff owned by the STT capability. It must start
under its bounded collector supervisor, monitor the coordinator and apply its own
finite drain deadline. Failure or stale authority prevents attachment. Queued
metadata and audio remain subject to their existing byte/count grants; settings
revocation closes active input/output grants, and workers independently recheck
authority every250ms. Re-enable/source replacement uses new run identity and only
future audio. A standalone worker is never selected for a known operational Silero
source.

Rejected: start a model/collector from the accepted-frame callback, retain a
mailbox of room requests, or derive source epochs from allocation IDs. Those would
respectively couple optional initialization to voice control, lose queue bounds,
or join different transport sources. The coordinator is an attachment mechanism,
not proof of persisted reports or acceptance of every live profile.

## Live report collection and coverage

The source-run report builder joins transient provider/canonical references and
accepted room/command IDs. It retains a bounded evidence window (default1,024
packets and1MiB charged packets plus derived reports; caps4,096/4MiB). Full capacity
fails collection explicitly; it does not silently remove history or borrow a later
turn. Reports change revision only when their evidence changes. Conflicting
provider associations cannot manufacture stage durations; valid room/response
stages remain visible independently.

Acoustic availability additionally requires an explicit mapping from cumulative
provider samples to the same source's normalized16kHz sample positions. Receipt
ordering alone is insufficient. The mapping packet and downstream consumer are
implemented; adapter production of verified anchors remains pending. Until then,
real collection cannot claim available acoustic durations from these modules.
Late unmapped boundaries conservatively invalidate uncertain estimates. Resets,
partial intervals, resumed speech and conflicting provenance remain nullable.

Calls owns the collector pool (default16, maximum32) alongside its existing writer
and task supervisors. Each collector uses byte/count-bounded capture, a bounded
report builder and the existing asynchronous persistence handoff. A250ms check
handles revocation and observed loss; heartbeats occur every second. On close,
capture stops first. Already admitted writes have at most2s to acknowledge settlement before a
terminal record is offered and the writer begins its independently bounded drain.
A missed deadline, discarded revision or known capture gap prevents complete
coverage. A failed terminal write leaves the prior running record to become
unconfirmed, rather than claiming that failure counters were durably delivered.
Writers monitor collector ownership, so abrupt collector loss starts finite drain.

This supplies a directly testable durable collector, not production activation.
Acknowledged provider profiles, actual sample-anchor emission, application wiring,
per-turn finalization policy and configured Scribe acceptance remain required.

Finalization uses explicit writer acknowledgments, not a transient zero-pending
counter snapshot. The observed-turn count includes storage-admission failures.
Unmatched-provider counts describe retained landmarks without one unambiguous
reportable provider identity (including suppressed many-to-one associations), not
raw wire-message traffic. Known losses prevent complete coverage even when the
remaining stored-row count matches.
