import type {
  ActivityEvent,
  Message,
  Metric,
  Participant,
  ProtocolEvent,
  ToolCall,
  VariableSnapshot,
} from "./types.js";

export type CallLifecycleState =
  | "prepared"
  | "admitting"
  | "running"
  | "ended"
  | "failed";

export interface CallIdentityAndLifecycle {
  id: string;
  revision: number;
  state: CallLifecycleState;
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
  terminalReason: string | null;
  /** Authoritative elapsed call duration when known. */
  durationMs: number | null;
}

export interface CallIncarnation {
  roomId: string;
  incarnationId: string;
}

export type UnavailableReason =
  | "not-loaded"
  | "not-captured"
  | "not-authorized"
  | "unsupported"
  | "known-gap";

export type Available<T> =
  | { state: "available"; value: T }
  | { state: "unavailable"; reason: UnavailableReason };

export type Availability =
  | { state: "available" }
  | { state: "unavailable"; reason: UnavailableReason };

export interface RevisionedEntity<T extends { id: string }> {
  id: string;
  revision: number;
  value: T;
}

interface TimelineEntityBase {
  id: string;
  revision: number;
  sourceSequence?: number;
}

export type CallDetailsTimelineEntity =
  | (TimelineEntityBase & { kind: "message"; value: Message })
  | (TimelineEntityBase & { kind: "activity"; value: ActivityEvent })
  | (TimelineEntityBase & { kind: "tool-call"; value: ToolCall })
  | (TimelineEntityBase & {
      kind: "protocol-event";
      value: ProtocolEvent;
    });

export interface MetricObservation {
  id: string;
  revision: number;
  value: Metric;
}

export interface CallDetailsCompleteness {
  state: "complete" | "incomplete" | "unconfirmed";
  missingSequenceCount: number;
  droppedLiveRecords: number;
}

export interface CallDetailsSnapshot {
  schemaVersion: 1;
  call: CallIdentityAndLifecycle;
  incarnation: CallIncarnation | null;
  participants: readonly RevisionedEntity<Participant>[];
  timeline: readonly CallDetailsTimelineEntity[];
  variables: Available<VariableSnapshot>;
  metrics: readonly MetricObservation[];
  metricsAvailability: Availability;
  completeness: CallDetailsCompleteness;
}

interface UpdateIdentity {
  callId: string;
  incarnationId?: string;
}

export type CallDetailsUpdate =
  | (UpdateIdentity & {
      type: "call-replace";
      value: CallIdentityAndLifecycle;
    })
  | (UpdateIdentity & {
      type: "participant-upsert";
      entity: RevisionedEntity<Participant>;
    })
  | (UpdateIdentity & {
      type: "participant-remove";
      id: string;
      revision: number;
    })
  | (UpdateIdentity & {
      type: "timeline-upsert";
      entity: CallDetailsTimelineEntity;
    })
  | (UpdateIdentity & {
      type: "timeline-remove";
      id: string;
      revision: number;
    })
  | (UpdateIdentity & {
      type: "metric-upsert";
      entity: MetricObservation;
    })
  | (UpdateIdentity & {
      type: "metric-remove";
      id: string;
      revision: number;
    })
  | (UpdateIdentity & {
      type: "variables-replace";
      revision: number;
      value: Available<VariableSnapshot>;
    });

export interface CallDetailsReader {
  getSnapshot(): CallDetailsSnapshot;
  subscribe(listener: () => void): () => void;
}

export interface CallDetailsStore extends CallDetailsReader {
  replaceBaseline(snapshot: CallDetailsSnapshot): boolean;
  apply(update: CallDetailsUpdate): boolean;
}

export interface CallDetailsLoader {
  refresh(signal: AbortSignal): Promise<CallDetailsSnapshot>;
}

export interface CallDetailsController extends CallDetailsReader {
  apply(update: CallDetailsUpdate): boolean;
  refresh(): Promise<void>;
  dispose(): void;
}

type CollectionName = "participants" | "timeline" | "metrics";

function timelineTime(entity: CallDetailsTimelineEntity) {
  return Date.parse(entity.value.occurredAt);
}

function compareTimeline(
  left: CallDetailsTimelineEntity,
  right: CallDetailsTimelineEntity,
) {
  const time = timelineTime(left) - timelineTime(right);
  if (time !== 0) return time;
  const sequence = (left.sourceSequence ?? Number.MAX_SAFE_INTEGER) -
    (right.sourceSequence ?? Number.MAX_SAFE_INTEGER);
  return sequence || left.id.localeCompare(right.id);
}

function copySnapshot(snapshot: CallDetailsSnapshot): CallDetailsSnapshot {
  return {
    ...snapshot,
    call: { ...snapshot.call },
    incarnation: snapshot.incarnation ? { ...snapshot.incarnation } : null,
    participants: [...snapshot.participants],
    timeline: [...snapshot.timeline].sort(compareTimeline),
    metrics: [...snapshot.metrics],
    metricsAvailability: { ...snapshot.metricsAvailability },
    completeness: { ...snapshot.completeness },
  };
}

function validRevision(revision: number) {
  return Number.isSafeInteger(revision) && revision >= 0;
}

export function createCallDetailsStore(
  initialSnapshot: CallDetailsSnapshot,
): CallDetailsStore {
  let snapshot = copySnapshot(initialSnapshot);
  const listeners = new Set<() => void>();
  let variablesRevision =
    snapshot.variables.state === "available" ? snapshot.variables.value.revision : -1;
  const tombstones: Record<CollectionName, Map<string, number>> = {
    participants: new Map(),
    timeline: new Map(),
    metrics: new Map(),
  };

  const notify = () => listeners.forEach((listener) => listener());
  const publish = (next: CallDetailsSnapshot) => {
    snapshot = next;
    notify();
  };
  const matches = (callId: string, incarnationId?: string) => {
    if (callId !== snapshot.call.id) return false;
    return (
      incarnationId === undefined ||
      snapshot.incarnation?.incarnationId === incarnationId
    );
  };
  const upsert = <T extends { id: string; revision: number }>(
    collection: CollectionName,
    values: readonly T[],
    entity: T,
  ) => {
    if (!validRevision(entity.revision)) return null;
    const removedAt = tombstones[collection].get(entity.id) ?? -1;
    const existing = values.find((value) => value.id === entity.id);
    if (entity.revision <= removedAt || entity.revision <= (existing?.revision ?? -1)) {
      return null;
    }
    return existing
      ? values.map((value) => (value.id === entity.id ? entity : value))
      : [...values, entity];
  };
  const remove = <T extends { id: string; revision: number }>(
    collection: CollectionName,
    values: readonly T[],
    id: string,
    revision: number,
  ) => {
    if (!validRevision(revision)) return null;
    const existing = values.find((value) => value.id === id);
    const removedAt = tombstones[collection].get(id) ?? -1;
    if (revision <= removedAt || revision <= (existing?.revision ?? -1)) return null;
    tombstones[collection].set(id, revision);
    return values.filter((value) => value.id !== id);
  };

  return {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    replaceBaseline(next) {
      if (next.call.id !== snapshot.call.id) return false;
      snapshot = copySnapshot(next);
      variablesRevision =
        snapshot.variables.state === "available" ? snapshot.variables.value.revision : -1;
      for (const values of Object.values(tombstones)) values.clear();
      notify();
      return true;
    },
    apply(update) {
      if (!matches(update.callId, update.incarnationId)) return false;
      switch (update.type) {
        case "call-replace":
          if (
            update.value.id !== snapshot.call.id ||
            update.value.revision <= snapshot.call.revision
          ) return false;
          publish({ ...snapshot, call: update.value });
          return true;
        case "participant-upsert": {
          const participants = upsert("participants", snapshot.participants, update.entity);
          if (!participants) return false;
          publish({ ...snapshot, participants });
          return true;
        }
        case "participant-remove": {
          const participants = remove(
            "participants",
            snapshot.participants,
            update.id,
            update.revision,
          );
          if (!participants) return false;
          publish({ ...snapshot, participants });
          return true;
        }
        case "timeline-upsert": {
          const existing = snapshot.timeline.find(
            (entity) => entity.id === update.entity.id,
          );
          if (existing?.kind === "protocol-event") return false;
          const timeline = upsert("timeline", snapshot.timeline, update.entity);
          if (!timeline) return false;
          publish({ ...snapshot, timeline: [...timeline].sort(compareTimeline) });
          return true;
        }
        case "timeline-remove": {
          const timeline = remove(
            "timeline",
            snapshot.timeline,
            update.id,
            update.revision,
          );
          if (!timeline) return false;
          publish({ ...snapshot, timeline: [...timeline].sort(compareTimeline) });
          return true;
        }
        case "metric-upsert": {
          const metrics = upsert("metrics", snapshot.metrics, update.entity);
          if (!metrics) return false;
          publish({ ...snapshot, metrics });
          return true;
        }
        case "metric-remove": {
          const metrics = remove(
            "metrics",
            snapshot.metrics,
            update.id,
            update.revision,
          );
          if (!metrics) return false;
          publish({ ...snapshot, metrics });
          return true;
        }
        case "variables-replace":
          if (!validRevision(update.revision) || update.revision <= variablesRevision) {
            return false;
          }
          variablesRevision = update.revision;
          publish({ ...snapshot, variables: update.value });
          return true;
      }
    },
  };
}

export function createCallDetailsController({
  store,
  loader,
}: {
  store: CallDetailsStore;
  loader?: CallDetailsLoader;
}): CallDetailsController {
  let disposed = false;
  let refreshController: AbortController | null = null;
  let bufferedUpdates: CallDetailsUpdate[] | null = null;

  return {
    getSnapshot: store.getSnapshot,
    subscribe: store.subscribe,
    apply(update) {
      if (disposed) return false;
      if (bufferedUpdates) bufferedUpdates.push(update);
      return store.apply(update);
    },
    async refresh() {
      if (disposed || !loader) return;
      refreshController?.abort();
      const controller = new AbortController();
      refreshController = controller;
      const updates: CallDetailsUpdate[] = [];
      bufferedUpdates = updates;
      try {
        const baseline = await loader.refresh(controller.signal);
        if (disposed || controller.signal.aborted) return;
        store.replaceBaseline(baseline);
        for (const update of updates) store.apply(update);
      } finally {
        if (refreshController === controller) refreshController = null;
        if (bufferedUpdates === updates) bufferedUpdates = null;
      }
    },
    dispose() {
      disposed = true;
      refreshController?.abort();
      bufferedUpdates = null;
    },
  };
}
