import { editSource, requireIdentifier } from "./editSource";
import type { CallSpecSource, MediaPolicy, Participant, SourceDocument } from "./types";

export function addParticipant(document: SourceDocument, key: string, type: Participant["type"]): SourceDocument {
  return editSource(document, (source) => {
    requireIdentifier(key);
    if (Object.hasOwn(source.participants, key)) throw new Error("That participant key already exists.");
    const participant: Participant = type === "agent"
      ? { type, prompt: "Help the caller.", tools: {}, transfers: [] }
      : { type, connection: { service: "web", mode: "receive", admission: "transfer" } };
    source.participants = { ...source.participants, [key]: participant };
  });
}

export function renameParticipant(document: SourceDocument, previous: string, next: string): SourceDocument {
  return editSource(document, (source) => {
    requireParticipant(source, previous);
    requireIdentifier(next);
    if (previous === next) return;
    if (Object.hasOwn(source.participants, next)) throw new Error("That participant key already exists.");
    source.participants = renameKey(source.participants, previous, next);
    rewriteReferences(source, previous, next);
  });
}

export function removeParticipant(document: SourceDocument, key: string): SourceDocument {
  return editSource(document, (source) => {
    requireParticipant(source, key);
    if (entryParticipant(source) === key) throw new Error("The entry participant cannot be removed.");
    delete source.participants[key];
    rewriteReferences(source, key, null);
  });
}

export function setTransfer(document: SourceDocument, from: string, to: string, enabled: boolean): SourceDocument {
  return editSource(document, (source) => {
    const participant = requireParticipant(source, from);
    if (participant.type !== "agent") throw new Error("Only agents can transfer a call.");
    if (enabled) {
      requireParticipant(source, to);
      if (from === to || entryParticipant(source) === to) throw new Error("Choose another transfer destination.");
    }
    const transfers = participant.transfers ?? [];
    participant.transfers = enabled ? [...new Set([...transfers, to])] : transfers.filter((target) => target !== to);
    cleanTransferVisibility(source, from);
  });
}

function requireParticipant(source: CallSpecSource, key: string): Participant {
  if (!Object.hasOwn(source.participants, key)) throw new Error("That participant no longer exists.");
  return source.participants[key]!;
}

function entryParticipant(source: CallSpecSource): string | undefined {
  return source.incoming_call?.caller ?? source.outgoing_call?.callee;
}

function renameKey<T>(map: Record<string, T>, previous: string, next: string | null): Record<string, T> {
  return Object.fromEntries(Object.entries(map).flatMap(([key, value]) =>
    key === previous ? (next === null ? [] : [[next, value]]) : [[key, value]],
  ));
}

function references(values: string[], previous: string, next: string | null): string[] {
  return values.flatMap((value) => value === previous ? (next === null ? [] : [next]) : [value]);
}

function routes(policy: MediaPolicy | undefined, previous: string, next: string | null): void {
  if (!policy) return;
  for (const field of ["audio_routes", "transcript_routes"] as const) {
    const map = policy[field];
    if (!map) continue;
    policy[field] = Object.fromEntries(Object.entries(renameKey(map, previous, next))
      .map(([key, recipients]) => [key, references(recipients, previous, next)]));
  }
}

function rewriteReferences(source: CallSpecSource, previous: string, next: string | null): void {
  if (source.incoming_call) {
    if (source.incoming_call.caller === previous) source.incoming_call.caller = next ?? "";
    if (source.incoming_call.handled_by === previous) source.incoming_call.handled_by = next ?? "";
  }
  if (source.outgoing_call) {
    if (source.outgoing_call.callee === previous) source.outgoing_call.callee = next ?? "";
    if (source.outgoing_call.handled_by === previous) source.outgoing_call.handled_by = next ?? "";
  }
  routes(source.media_policy, previous, next);
  if (source.tool_visibility_overrides) source.tool_visibility_overrides = renameKey(source.tool_visibility_overrides, previous, next);
  for (const [key, participant] of Object.entries(source.participants)) {
    routes(participant.while_present, previous, next);
    if (participant.type === "agent" && participant.transfers) {
      participant.transfers = references(participant.transfers, previous, next);
      cleanTransferVisibility(source, key);
    }
  }
}

function cleanTransferVisibility(source: CallSpecSource, key: string): void {
  const participant = source.participants[key];
  const overrides = source.tool_visibility_overrides;
  if (participant?.type === "agent" && !participant.transfers?.length && overrides && Object.hasOwn(overrides, key)) {
    delete overrides[key]!.transfer;
  }
}
