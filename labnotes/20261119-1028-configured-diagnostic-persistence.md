# Configured diagnostic persistence

Production composition e151f294 is pushed. Its frozen root suite is terminal;
the retained log reports zero failures for every application, ending Console592/0.
The original process handle has expired, so its exit code was not recovered.
No source/test/build edits until that baseline completes. Existing fixture research:
Console's ElevenLabs configured-room test provisions encrypted credentials and
runs real Scribe room startup, but currently uses two humans and a readiness-only
fake transport. The new acceptance must use an LLM agent, actual socket receipt
callbacks/acknowledged profile, durable call claim/incarnation binding, and the
production diagnostic parent with a Persistence repository.

Use Calls.claim_call/claim_join_token to obtain the durable resolved plan, start
that plan through Engine, bind its actual incarnation before connecting speech,
and attach Console SpeechConnection. The actual model fixture can supply response
text. Source ingress supplies transport epochs. A controlled diagnostic classifier
can delay an actual pinned Silero result until after provider settlement, while
retaining real source PCM and mapping. This is fixture acceptance, not live transport
accuracy. Existing live fixture PCM has real-model boundary expectations elsewhere.

Inspection identified a likely blocker to the required pending-row/late-confirmation
case: SourceWorker.pump stops whenever inference is active, including queued provider
and room timing packets. An isolated red probe is testing a provider end packet
while inference remains blocked. The first test selection pointed at setup and
excluded the test; corrected selection is line95. Temporary probes preserve the
running root suite's source snapshot.

The focused source worker timing probe is red1/1: provider end cannot pass a held
inference. The configured fixture now reaches the same real failure after ordinary
call claim, encrypted Scribe credential resolution, actual room/speech readiness,
source discovery, durable run creation and actual pinned Silero input batches.
Its provider turn completes but no pending turn row is written before held final
inference is released (500ms assertion). Earlier fixture failures were harness
errors, not product defects: ConnectionAttachment has no identity fields (use the
AttachConnection command), frames must carry their explicit source epoch, and
LatencyStore.list_runs returns a paginated entries map rather than a bare list.
The working red fixture is vxpipe_configured_latency_test.exs.

Astra design review reproduced two hazards with naive timing overtaking: an earlier
endpoint transiently yields an available500ms duration before resumed speech is
processed; a gap detected after provider end is ignored by wall-time filtering.
The temporary tests vxpipe_live_report_overtaking_review_test.exs are red2/2.
Processing all model windows is also insufficient: pending onset frames can later
backdate a boundary into processed audio (20992processed,20480finalized).

Chosen smallest coverage contract under review: immediate bounded forwarding of
provider/room/response metadata, plus coalesced acoustic progress per inference
epoch carrying contiguous source origin and finalized-through sample. Advance only
after boundaries, subtracting unconfirmed onset/silence windows. Require the selected
endpoint and mapped provider-end sample to share that finalized epoch interval;
otherwise acoustic landmarks/durations remain missing while independent stages
persist. Never extend an old epoch across a gap/reset. Gap notices use original
frame receipt time; reset epoch/coverage carries failure evidence when processing
is late. These changes are not implemented yet.

Finalized-prefix prerequisite now has retained red/green tests: pending onset1–3
and silence1–15 windows do not advance finalized samples; confirmation, discarded
candidates and reset release/reset the prefix correctly. CapturePacket accepts only
bounded epoch/origin/finalized integer tuples and rejects reversed/oversized ranges
or extra fields. Focused8/0 after expected missing-function/invalid-packet reds.
Format, compile warnings-as-errors, strict Credo, unused-lock and Lean pass.
Astra xhigh review is clean: independent8/0 plus20 reachable detector states and60
transitions confirm monotonic finalized progress and no later boundary below it.
The finalized interval is half-open; a later boundary may equal its upper bound.
Frozen root suite vxpipe-progress-umbrella.log is active (session49144).
No SourceWorker emission or LiveReport consumption has changed yet. The temporary
LiveProgressContractTest describes pending independent provider stages, late acoustic
revision, bounded progress coalescing and conflicting epoch-origin rejection.

The temporary live-progress contract is red1/1 because LiveReport does not yet
accept acoustic_progress. This is the next implementation boundary. Working tree
contains only the reviewed four prerequisite source/test files and this labnote;
no acceptance checklist item is newly complete. No deployment performed.
