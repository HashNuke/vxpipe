import type { SourceDocument } from "./types";

export type ParticipantNode = {
  id: string;
  kind: "entry" | "agent" | "human";
  participantKey: string;
  locked: boolean;
  position: { x: number; y: number };
};
export type TransferEdge = { id: string; source: string; target: string; locked: boolean };
export type ParticipantGraph = { nodes: ParticipantNode[]; edges: TransferEdge[] };

export function projectGraph({ source }: SourceDocument): ParticipantGraph {
  const entry = source.incoming_call?.caller ?? source.outgoing_call?.callee ?? source.entry_caller ?? "";
  const handler = source.incoming_call?.handled_by ?? source.outgoing_call?.handled_by ?? source.entry_receiver ?? "";
  const ordered: string[] = [];
  const seen = new Set<string>([entry]);
  const queue = [handler];
  for (let index = 0; index < queue.length; index++) {
    const key = queue[index]!;
    if (seen.has(key) || !source.participants[key]) continue;
    seen.add(key);
    ordered.push(key);
    const participant = source.participants[key];
    if (participant?.type === "agent" && Array.isArray(participant.transfers)) queue.push(...participant.transfers);
  }
  ordered.push(...Object.keys(source.participants).filter((key) => !seen.has(key)).sort());
  const agents = ordered.filter((key) => source.participants[key]?.type === "agent");
  const humans = ordered.filter((key) => source.participants[key]?.type === "human");
  const nodes: ParticipantNode[] = [
    { id: "$entry", kind: "entry", participantKey: entry, locked: true, position: { x: 0, y: 0 } },
    ...agents.map((key, index): ParticipantNode => ({ id: key, kind: "agent", participantKey: key, locked: false, position: { x: 320, y: index * 180 } })),
    ...humans.map((key, index): ParticipantNode => ({ id: key, kind: "human", participantKey: key, locked: false, position: { x: 640, y: index * 180 } })),
  ];
  const edges: TransferEdge[] = handler ? [{ id: "$entry-edge", source: "$entry", target: handler, locked: true }] : [];
  for (const key of agents) {
    const participant = source.participants[key];
    if (participant?.type !== "agent" || !Array.isArray(participant.transfers)) continue;
    for (const target of participant.transfers) {
      edges.push({ id: `transfer:${key}:${target}`, source: key, target: target === entry ? "$entry" : target, locked: false });
    }
  }
  return { nodes, edges };
}
