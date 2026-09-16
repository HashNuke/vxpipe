import type {
  ActivityEvent,
  Availability,
  Available,
  CallDetailsSnapshot,
  CallDetailsTimelineEntity,
  CallLifecycleState,
  JsonValue,
  Metric,
  MetricObservation,
  MetricScope,
  Participant,
  ProtocolEvent,
  RevisionedEntity,
  ToolCall,
  VariableSnapshot,
} from "@vxpipe/core";

type ObjectValue = Record<string, unknown>;

export class CallInspectionResponseError extends Error {
  readonly status: number | null;

  constructor(message: string, status: number | null = null) {
    super(message);
    this.name = "CallInspectionResponseError";
    this.status = status;
  }
}

export function createCallInspectionLoader(tenantKey: string, callId: string) {
  return {
    async refresh(signal: AbortSignal): Promise<CallDetailsSnapshot> {
      const response = await fetch(
        `/tenants/${encodeURIComponent(tenantKey)}/calls/${encodeURIComponent(callId)}/inspection`,
        {
          signal,
          credentials: "same-origin",
          cache: "no-store",
          headers: { accept: "application/json" },
        },
      );

      if (!response.ok) {
        throw new CallInspectionResponseError(
          `Call inspection is unavailable (${response.status}).`,
          response.status,
        );
      }

      let body: unknown;
      try {
        body = await response.json();
      } catch {
        signal.throwIfAborted();
        throw new CallInspectionResponseError(
          "Call inspection returned malformed JSON.",
        );
      }
      const snapshot = parseCallInspectionResponse(body);
      if (snapshot.call.id !== callId) {
        throw new CallInspectionResponseError(
          "Call inspection returned a different call.",
        );
      }
      return snapshot;
    },
  };
}

export function parseCallInspectionResponse(value: unknown): CallDetailsSnapshot {
  const root = object(value, "response");
  literal(root.schema_version, 1, "schema_version");

  return {
    schemaVersion: 1,
    call: call(root.call),
    incarnation: incarnation(root.incarnation),
    participants: array(root.participants, "participants").map((entry, index) =>
      participant(entry, `participants[${index}]`),
    ),
    timeline: array(root.timeline, "timeline").map((entry, index) =>
      timelineEntity(entry, `timeline[${index}]`),
    ),
    variables: availability(
      root.variables,
      "variables",
      variableSnapshot,
    ),
    metrics: array(root.metrics, "metrics").map((entry, index) =>
      metricObservation(entry, `metrics[${index}]`),
    ),
    metricsAvailability: simpleAvailability(
      root.metrics_availability,
      "metrics_availability",
    ),
    completeness: completeness(root.completeness),
  };
}

function call(value: unknown): CallDetailsSnapshot["call"] {
  const item = object(value, "call");
  return {
    id: string(item.id, "call.id"),
    revision: revision(item.revision, "call.revision"),
    state: member(
      item.state,
      ["prepared", "admitting", "running", "ended", "failed"] as const,
      "call.state",
    ) as CallLifecycleState,
    createdAt: instant(item.created_at, "call.created_at"),
    startedAt: nullableInstant(item.started_at, "call.started_at"),
    endedAt: nullableInstant(item.ended_at, "call.ended_at"),
    terminalReason: nullableString(item.terminal_reason, "call.terminal_reason"),
    durationMs: nullableNonnegativeNumber(item.duration_ms, "call.duration_ms"),
  };
}

function incarnation(value: unknown): CallDetailsSnapshot["incarnation"] {
  if (value === null) return null;
  const item = object(value, "incarnation");
  return {
    roomId: string(item.room_id, "incarnation.room_id"),
    incarnationId: string(item.incarnation_id, "incarnation.incarnation_id"),
  };
}

function participant(
  value: unknown,
  path: string,
): RevisionedEntity<Participant> {
  const entity = object(value, path);
  const item = object(entity.value, `${path}.value`);
  const connection = participantConnection(item.connection, `${path}.value.connection`);

  return {
    id: string(entity.id, `${path}.id`),
    revision: revision(entity.revision, `${path}.revision`),
    value: {
      id: string(item.id, `${path}.value.id`),
      name: string(item.name, `${path}.value.name`),
      role: member(
        item.role,
        ["caller", "agent", "human"] as const,
        `${path}.value.role`,
      ),
      state: member(
        item.state,
        ["inactive", "listening", "speaking", "left"] as const,
        `${path}.value.state`,
      ),
      description: nullableString(item.description, `${path}.value.description`),
      ...(connection ? { connection } : {}),
      capabilities: array(item.capabilities, `${path}.value.capabilities`).map(
        (entry, index) => {
          const capability = object(
            entry,
            `${path}.value.capabilities[${index}]`,
          );
          const model = optionalString(
            capability.model,
            `${path}.value.capabilities[${index}].model`,
          );
          return {
            name: string(
              capability.name,
              `${path}.value.capabilities[${index}].name`,
            ),
            provider: string(
              capability.provider,
              `${path}.value.capabilities[${index}].provider`,
            ),
            ...(model === undefined ? {} : { model }),
          };
        },
      ),
      systemPrompt: nullableString(item.system_prompt, `${path}.value.system_prompt`),
      transferPolicies: namedDescriptions(
        item.transfer_policies,
        `${path}.value.transfer_policies`,
      ),
      tools: namedDescriptions(item.tools, `${path}.value.tools`),
    },
  };
}

function participantConnection(value: unknown, path: string) {
  if (value === null || value === undefined) return undefined;
  const item = object(value, path);
  const kind = member(item.kind, ["webrtc", "phone"] as const, `${path}.kind`);
  return kind === "phone"
    ? { kind, phoneNumber: string(item.phone_number, `${path}.phone_number`) } as const
    : { kind } as const;
}

function namedDescriptions(value: unknown, path: string) {
  return array(value, path).map((entry, index) => {
    const item = object(entry, `${path}[${index}]`);
    return {
      name: string(item.name, `${path}[${index}].name`),
      description: string(item.description, `${path}[${index}].description`),
    };
  });
}

function timelineEntity(value: unknown, path: string): CallDetailsTimelineEntity {
  const entity = object(value, path);
  const kind = member(
    entity.kind,
    ["message", "activity", "tool-call", "protocol-event"] as const,
    `${path}.kind`,
  );
  const base = {
    id: string(entity.id, `${path}.id`),
    revision: revision(entity.revision, `${path}.revision`),
    ...(entity.source_sequence === undefined
      ? {}
      : { sourceSequence: revision(entity.source_sequence, `${path}.source_sequence`) }),
  };

  if (kind === "message") {
    const item = object(entity.value, `${path}.value`);
    return {
      ...base,
      kind,
      value: {
        id: string(item.id, `${path}.value.id`),
        participantId: string(item.participant_id, `${path}.value.participant_id`),
        text: string(item.text, `${path}.value.text`),
        occurredAt: instant(item.occurred_at, `${path}.value.occurred_at`),
        state: member(
          item.state,
          ["final", "streaming", "interrupted"] as const,
          `${path}.value.state`,
        ),
      },
    };
  }

  if (kind === "activity") {
    return { ...base, kind, value: activity(entity.value, `${path}.value`) };
  }
  if (kind === "protocol-event") {
    return { ...base, kind, value: protocolEvent(entity.value, `${path}.value`) };
  }
  return { ...base, kind, value: toolCall(entity.value, `${path}.value`) };
}

function activity(value: unknown, path: string): ActivityEvent {
  const item = object(value, path);
  return {
    id: string(item.id, `${path}.id`),
    occurredAt: instant(item.occurred_at, `${path}.occurred_at`),
    text: string(item.text, `${path}.text`),
    kind: member(item.kind, ["call", "participant", "transfer"] as const, `${path}.kind`),
  };
}

function protocolEvent(value: unknown, path: string): ProtocolEvent {
  const item = object(value, path);
  return {
    id: string(item.id, `${path}.id`),
    protocol: string(item.protocol, `${path}.protocol`),
    type: string(item.type, `${path}.type`),
    direction: member(item.direction, ["in", "out"] as const, `${path}.direction`),
    occurredAt: instant(item.occurred_at, `${path}.occurred_at`),
    summary: string(item.summary, `${path}.summary`),
    details: object(item.details, `${path}.details`),
  };
}

function toolCall(value: unknown, path: string): ToolCall {
  const item = object(value, path);
  const request = optionalJson(item.request, `${path}.request`);
  const response = optionalJson(item.response, `${path}.response`);
  const responseStatus = optionalInteger(item.response_status, `${path}.response_status`);
  return {
    id: string(item.id, `${path}.id`),
    occurredAt: instant(item.occurred_at, `${path}.occurred_at`),
    name: string(item.name, `${path}.name`),
    status: member(
      item.status,
      ["pending", "completed", "failed"] as const,
      `${path}.status`,
    ),
    ...(request === undefined ? {} : { request }),
    ...(response === undefined ? {} : { response }),
    ...(responseStatus === undefined ? {} : { responseStatus }),
  };
}

function metricObservation(value: unknown, path: string): MetricObservation {
  const entity = object(value, path);
  return {
    id: string(entity.id, `${path}.id`),
    revision: revision(entity.revision, `${path}.revision`),
    value: metric(entity.value, `${path}.value`),
  };
}

function metric(value: unknown, path: string): Metric {
  const item = object(value, path);
  return {
    label: string(item.label, `${path}.label`),
    value: nullableNumber(item.value, `${path}.value`),
    unit: string(item.unit, `${path}.unit`),
    source: string(item.source, `${path}.source`),
    description: string(item.description, `${path}.description`),
    scope: metricScope(item.scope, `${path}.scope`),
  };
}

function metricScope(value: unknown, path: string): MetricScope {
  const item = object(value, path);
  const kind = member(
    item.kind,
    ["room", "room-capability", "participant", "participant-capability"] as const,
    `${path}.kind`,
  );
  if (kind === "room") return { kind };
  if (kind === "room-capability") {
    return { kind, capability: string(item.capability, `${path}.capability`) };
  }
  if (kind === "participant") {
    return { kind, participantId: string(item.participant_id, `${path}.participant_id`) };
  }
  return {
    kind,
    participantId: string(item.participant_id, `${path}.participant_id`),
    capability: string(item.capability, `${path}.capability`),
  };
}

function variableSnapshot(value: unknown, path: string): VariableSnapshot {
  const item = object(value, path);
  const sections = object(item.sections, `${path}.sections`);
  return {
    revision: revision(item.revision, `${path}.revision`),
    sections: Object.fromEntries(
      Object.entries(sections).map(([name, sectionValue]) => {
        const section = object(sectionValue, `${path}.sections.${name}`);
        return [
          name,
          {
            revision: revision(section.revision, `${path}.sections.${name}.revision`),
            value: json(section.value, `${path}.sections.${name}.value`),
          },
        ];
      }),
    ),
  };
}

function completeness(value: unknown): CallDetailsSnapshot["completeness"] {
  const item = object(value, "completeness");
  return {
    state: member(
      item.state,
      ["complete", "incomplete", "unconfirmed"] as const,
      "completeness.state",
    ),
    missingSequenceCount: revision(
      item.missing_sequence_count,
      "completeness.missing_sequence_count",
    ),
    droppedLiveRecords: revision(
      item.dropped_live_records,
      "completeness.dropped_live_records",
    ),
  };
}

function availability<T>(
  value: unknown,
  path: string,
  parse: (value: unknown, path: string) => T,
): Available<T> {
  const item = object(value, path);
  const state = member(item.state, ["available", "unavailable"] as const, `${path}.state`);
  return state === "available"
    ? { state, value: parse(item.value, `${path}.value`) }
    : { state, reason: unavailableReason(item.reason, `${path}.reason`) };
}

function simpleAvailability(value: unknown, path: string): Availability {
  const item = object(value, path);
  const state = member(item.state, ["available", "unavailable"] as const, `${path}.state`);
  return state === "available"
    ? { state }
    : { state, reason: unavailableReason(item.reason, `${path}.reason`) };
}

function unavailableReason(value: unknown, path: string) {
  return member(
    value,
    ["not-loaded", "not-captured", "not-authorized", "unsupported", "known-gap"] as const,
    path,
  );
}

function object(value: unknown, path: string): ObjectValue {
  if (typeof value !== "object" || value === null || Array.isArray(value)) invalid(path);
  return value as ObjectValue;
}

function array(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) invalid(path);
  return value;
}

function string(value: unknown, path: string): string {
  if (typeof value !== "string") invalid(path);
  return value;
}

function nullableString(value: unknown, path: string): string | null {
  return value === null ? null : string(value, path);
}

function optionalString(value: unknown, path: string): string | undefined {
  return value === undefined ? undefined : string(value, path);
}

function instant(value: unknown, path: string): string {
  const result = string(value, path);
  if (!Number.isFinite(Date.parse(result))) invalid(path);
  return result;
}

function nullableInstant(value: unknown, path: string): string | null {
  return value === null ? null : instant(value, path);
}

function revision(value: unknown, path: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) invalid(path);
  return value as number;
}

function nullableNumber(value: unknown, path: string): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) invalid(path);
  return value;
}

function nullableNonnegativeNumber(value: unknown, path: string): number | null {
  const result = nullableNumber(value, path);
  if (result !== null && result < 0) invalid(path);
  return result;
}

function optionalInteger(value: unknown, path: string): number | undefined {
  if (value === undefined) return undefined;
  if (!Number.isInteger(value)) invalid(path);
  return value as number;
}

function literal(value: unknown, expected: unknown, path: string): void {
  if (value !== expected) invalid(path);
}

function member<const T extends readonly string[]>(
  value: unknown,
  values: T,
  path: string,
): T[number] {
  if (typeof value !== "string" || !values.includes(value)) invalid(path);
  return value as T[number];
}

function optionalJson(value: unknown, path: string): JsonValue | undefined {
  return value === undefined ? undefined : json(value, path);
}

function json(value: unknown, path: string): JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value))
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry, index) => json(entry, `${path}[${index}]`));
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, json(entry, `${path}.${key}`)]),
    );
  }
  return invalid(path);
}

function invalid(path: string): never {
  throw new CallInspectionResponseError(`Invalid call inspection field: ${path}.`);
}
