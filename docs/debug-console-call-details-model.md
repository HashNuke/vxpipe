# Debug-console call details model

Status: proposed design for the Core/React implementation; the Storybook prototype has not yet
migrated to this model.

## Problem

The debug console must render the same call while it is changing and after it has been loaded from
an authorized remote history endpoint. A live transcript, tool call, variable set, metric, or
participant can be revised after its first event. Delivery can repeat, arrive out of order, or be
interrupted. Persisted history is cursor-paginated and can be incomplete. Browser microphone and
speaker state exist only for the current local seat and do not belong in a historical call record.

The prototype's flat `CallSnapshot` mixes call facts with local device state and replaces whole
arrays. That is acceptable fixture data, but it is not the production storage or update contract.

## Decision

Core owns a normalized, serializable call-details model and derives immutable React snapshots from
it. Live RTVI, Calls live inspection, and Calls persisted inspection are adapters into that model;
React components do not distinguish which adapter supplied a fact. Commands and local media state
are separate optional inputs, so a historical call uses the same viewer without pretending it has
a microphone, an active transport, or callable actions.

The public concepts are:

```ts
interface CallDetailsSnapshot {
  schemaVersion: 1;
  call: CallIdentityAndLifecycle;
  incarnation: CallIncarnation | null;
  participants: readonly ParticipantDetails[];
  timeline: readonly TimelineItem[];
  variables: Available<VariableSnapshot>;
  metrics: readonly MetricObservation[];
  completeness: CallDetailsCompleteness;
  olderCursor: string | null;
  asOf: string;
}

interface CallDetailsStore {
  getSnapshot(): CallDetailsSnapshot;
  subscribe(listener: () => void): () => void;
  loadOlder?(): Promise<void>;
  refresh?(): Promise<void>;
}

interface LiveCallControls {
  getLocalSession(): LocalSessionSnapshot;
  subscribeLocalSession(listener: () => void): () => void;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  sendText(text: string): Promise<void>;
  // microphone, speaker, and device commands
}
```

`Available<T>` distinguishes a value from `unavailable`, with bounded reasons such as not loaded,
not captured, not authorized, unsupported, or lost through a known gap. An absent tool response is
therefore different from a captured JSON `null`, and a denied system prompt is different from an
empty prompt.

The wire snapshot uses arrays because it must be JSON-safe. The Core store indexes participants,
timeline items, and metric observations by stable ID internally. It exposes ordered immutable
arrays to React through selectors. Components key rows by those IDs and never by array position.

## Identity, revisions, and order

Every semantic entity has a stable ID and a monotonically increasing entity revision. An initial
streaming message, its next text fragment, and its final form share one ID. Tool start and terminal
updates share one tool-call ID. Metric updates share an observation ID. A newer revision replaces
the prior normalized entity; duplicate and older revisions are ignored. Removal requires an
explicit tombstone. Core does not perform an arbitrary deep merge because omission can mean either
unchanged or unavailable depending on the source.

An immutable persisted fact enters at revision 1. If a live protocol supplies an explicit revision,
the adapter preserves it. If a protocol supplies ordered updates without revisions, its adapter may
assign revisions only within the current baseline and must obtain a new authoritative baseline after
reconnect. A partial protocol update is decoded against the adapter's known prior value and emitted
to Core as a complete replacement; the generic store does not interpret transport-specific patches.

Updates are collection-specific (`timeline upsert`, `participant upsert`, `variables replace`,
`metric upsert`, lifecycle update, or tombstone) and include the call ID and incarnation ID where
applicable. An update for an older call incarnation cannot change the current call.

Timeline display order is derived from authoritative occurrence time, source sequence when one is
available, and stable ID as the final tie-breaker. Arrival order alone is not a display contract.
The current Calls projection already supplies immutable fact IDs, source sequences, occurrence
times, call/room/incarnation identities, tool-call correlation, and variable revisions. Streaming
adapters must preserve or construct equivalent semantic identity before updating Core.

Raw RTVI log receipts are different from semantic timeline entities. Logs are append-only observed
traffic, including repeats, and retain their own receipt identity and order. An RTVI event that
corrects a transcript updates the semantic message while both protocol receipts can remain visible
when the Logs filter is enabled.

## Loading and reconciling a call

A historical adapter loads the newest authorized Calls inspection page first and follows its
opaque `next_cursor` when the user requests older history. Overlapping pages are safe because Core
deduplicates by entity ID and revision. The adapter may also read the selected immutable
call-details publication for authorized participant configuration, tools, transfers, usage,
variables, and artifacts. It must retain the server's completeness and archive-gap information;
loading a page never implies that the whole call is complete.

A live adapter establishes a baseline before applying updates. It combines participant-visible
RTVI facts with the tenant-authorized live inspection projection only at the authorized Console
boundary. The live projection's fact sequence, variable revision, dropped-record count, rejected-
record count, room ID, and incarnation ID make loss and stale updates visible. If a reconnect,
sequence gap, changed incarnation, or bounded-buffer drop prevents safe continuation, the adapter
refreshes an authoritative snapshot instead of guessing a patch. Updates received during the
refresh are buffered and applied only after the baseline revision they follow.

Persisted history can replace equivalent live entities when it has the same stable source identity.
If two sources cannot prove that identity, Core preserves both facts and their provenance instead
of merging them heuristically. The final archive status remains `complete`, `incomplete`, or
`unconfirmed`, matching the existing Calls contract.

## React boundary

`CallConsole` consumes the read-only `CallDetailsStore` and accepts `LiveCallControls` only when the
current page owns a live debug seat. Conversation, Variables, Metrics, and Participants render from
the store in both modes. The composer, call button, and device controls render from the optional
live controls. Starting a new call creates a new store/incarnation rather than clearing a remotely
loaded historical record in place.

Selectors build the current presentation rows from normalized entities. This keeps update,
pagination, deduplication, authorization availability, and resynchronization logic out of React
components. A component rerenders when its selected entity revision changes; it does not need to
know whether the change came from RTVI, a live-inspection refresh, or a historical fetch.

## Rejected alternatives

- One ever-growing `CallSnapshot` containing device state, remote history, and commands: it cannot
  represent a read-only historical call cleanly and encourages whole-array replacement.
- Rendering RTVI packets directly: private participant configuration and durable history do not
  belong to ordinary RTVI, and reconnect gaps cannot be repaired from a packet stream alone.
- Generic JSON patches: partial omission, redaction, and explicit empty values have different
  meanings, so unconstrained deep merging can retain stale or unauthorized data.
- Ordering by receipt time: reconnection, batching, and remote pagination can reorder receipts.
- Rebuilding a second browser history store: Calls already owns authorized pagination,
  completeness, archive gaps, variable revisions, and immutable call-details publications.

## Implementation and verification

Migrate in a focused Core checkpoint before connecting a real transport:

1. Define the serializable types, normalized reducer, selectors, data-store interface, and separate
   live-control interface.
2. Adapt the existing Storybook fixture through the store so the current UI remains reviewable.
3. Prove newer/duplicate/stale revisions, tombstones, out-of-order updates, incarnation rejection,
   variable replacement, page overlap, deterministic ordering, and known gaps in Core tests.
4. Render the same call from a replayed live-update fixture and a historical snapshot fixture and
   assert the resulting presentation is equivalent.
5. Verify unavailable/redacted fields, an incomplete archive, a read-only historical call, older-
   page loading, reconnect resynchronization, and browser cleanup.

This design does not claim that current RTVI messages provide all required identity or revisions.
The roster/output-attribution wire design remains a gate: an adapter may emit a normalized update
only when its source provides enough identity to apply it safely.
