# Debug-console call details model

Status: Core store/controller and React consumption implemented in the private TypeScript packages;
real Console endpoint and RTVI adapters remain pending.

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
it. The Console host fetches an authorized call-details payload and hands it to Core for both
ongoing and ended calls. Core and React do not know the endpoint, authentication, or tenant API.
RTVI supplies only the live edge while this browser is attached to a live call. React components
do not distinguish which source supplied a normalized fact. Commands and local media state are
separate optional inputs, so a historical call uses the same viewer without pretending it has a
microphone, an active transport, or callable actions.

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
  replaceBaseline(snapshot: CallDetailsSnapshot): boolean;
  mergePage(page: CallDetailsPage): boolean;
  apply(update: CallDetailsUpdate): boolean;
}

interface CallDetailsLoader {
  refresh(signal: AbortSignal): Promise<CallDetailsSnapshot>;
  loadOlder(cursor: string, signal: AbortSignal): Promise<CallDetailsPage>;
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

The host composition is deliberately small:

```ts
const initialDetails = await callsApi.fetchDetails(callId);
const store = createCallDetailsStore(initialDetails);
const rtvi = debugSeat ? createRtviSession(debugSeat) : undefined;

const controller = createCallConsoleController({
  store,
  loader: {
    refresh: (signal) => callsApi.fetchDetails(callId, { signal }),
    loadOlder: (cursor, signal) => callsApi.fetchHistory(callId, { cursor, signal }),
  },
  liveUpdates: rtvi?.updates,
  liveControls: rtvi?.controls,
});
```

`@vxpipe/react` receives `controller`; it never receives `callsApi`. A host that already loaded the
entire ended call may omit the loader. Storybook supplies an in-memory loader and the same data
shape.

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

The Console host is the data owner for every existing call, including one that is still ongoing.
It fetches the newest authorized Calls inspection payload, creates the Core store with that initial
snapshot, and injects endpoint-specific `refresh` and `loadOlder` callbacks. When the viewer requests
older history, the host callback follows the opaque `next_cursor` and returns the page to Core.
Overlapping pages are safe because Core deduplicates by entity ID and revision. The host may also
compose the selected immutable call-details publication into the supplied snapshot for authorized
participant configuration, tools, transfers, usage, variables, and artifacts. It passes through
the server's completeness and archive-gap information; loading a page never implies that the whole
call is complete.

For an ongoing call, the host can refresh newer accumulated history and include the tenant-
authorized bounded live-inspection projection in the supplied payload. Opening an ongoing call does
not require the operator to join its RTVI session. If this browser does attach as a live debug seat,
the RTVI adapter applies low-latency updates after the supplied baseline. The live projection's fact
sequence, variable revision, dropped-record count, rejected-record count, room ID, and incarnation
ID make loss and stale updates visible. If a reconnect, sequence gap, changed incarnation, or
bounded-buffer drop prevents safe continuation, Core invokes the injected refresh callback instead
of guessing a patch. Updates received during the refresh are buffered and applied only after the
baseline revision they follow.

Once a call ends, Core has no RTVI dependency. The host fetches its durable timeline and final
details and hands that payload to the same store. RTVI receipts seen only by an attached browser are
available in a later remote view only if the platform deliberately captured and authorized those
receipts; their absence is reported as unavailable and is not confused with an empty log.

Persisted history can replace equivalent live entities when it has the same stable source identity.
If two sources cannot prove that identity, Core preserves both facts and their provenance instead
of merging them heuristically. The final archive status remains `complete`, `incomplete`, or
`unconfirmed`, matching the existing Calls contract.

## React boundary

`CallConsole` consumes the read-only side of `CallDetailsStore` and receives controller actions that
wrap the injected loading callbacks. It accepts `LiveCallControls` only when the current page owns a
live debug seat. Conversation, Variables, Metrics, and Participants render from the supplied store
in both modes. The composer, call button, and device controls render from the optional live
controls. Starting a new call creates a new store/incarnation rather than clearing a remotely loaded
historical record in place.

Selectors build the current presentation rows from normalized entities. This keeps update,
pagination, deduplication, authorization availability, and resynchronization logic out of React
components. A component rerenders when its selected entity revision changes; it does not need to
know whether the change came from RTVI, a live-inspection refresh, or a historical fetch.

## Rejected alternatives

- One ever-growing `CallSnapshot` containing device state, remote history, and commands: it cannot
  represent a read-only historical call cleanly and encourages whole-array replacement.
- Rendering RTVI packets directly: RTVI is the live transport, while private participant
  configuration and durable history come from the remote Calls endpoint. Reconnect gaps and ended
  calls cannot be reconstructed from a browser packet stream alone.
- Generic JSON patches: partial omission, redaction, and explicit empty values have different
  meanings, so unconstrained deep merging can retain stale or unauthorized data.
- Ordering by receipt time: reconnection, batching, and remote pagination can reorder receipts.
- Rebuilding a second browser history store: Calls already owns authorized pagination,
  completeness, archive gaps, variable revisions, and immutable call-details publications.

## Implementation and verification

The private Core/React checkpoint now provides:

1. Serializable types, normalized reducer, selectors, injected loader/store interfaces, and a
   separate live-control interface.
2. Storybook fixtures using the same controller boundary, including remote-ended, remote-ongoing,
   and attached-live states.
3. Core tests for newer/duplicate/stale revisions, tombstones, call-incarnation rejection, raw RTVI
   receipt immutability, variable/page reconciliation, deterministic ordering, completeness/gaps,
   and live-update replay across baseline refresh.
4. React tests that hydrate typed mock endpoint responses and render ongoing and ended calls without
   live controls, alongside the existing attached-live interaction suite.
5. TypeScript ESM/declaration builds, package tarball dry runs, Storybook production build, and
   rendered desktop/390px review.

The real Console endpoint adapter, runtime response validation, RTVI decoder, WebRTC transport, and
authorized browser routes are later implementation checkpoints.

This design does not claim that current RTVI messages provide all required identity or revisions.
The roster/output-attribution wire design remains a gate: an adapter may emit a normalized update
only when its source provides enough identity to apply it safely.
