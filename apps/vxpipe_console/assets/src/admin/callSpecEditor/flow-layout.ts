import type { Edge, Node } from "@xyflow/react";
import { projectGraph } from "./graph";
import { isTransferDestination } from "./participants";
import type { SourceDocument } from "./types";

// Callpipe card geometry; source graph order replaces its mutable Dagre graph.
export const FLOW_NODE_WIDTH = 320;
export const FLOW_LAYOUT_NODE_SEPARATION = 80;
export const FLOW_LAYOUT_MARGIN = 48;
export type FlowNodeData = {
  kind: "entry" | "agent" | "human";
  label: string;
  subtitle: string;
  toolCount: number;
  variableCount: number;
  issueCount: number;
  readOnly: boolean;
};
export type CanvasNode = Node<FlowNodeData, "flowNode">;

export function canvasGraph(document: SourceDocument, selectedNodeId: string | null = null, issues: Record<string, number> = {}): { nodes: CanvasNode[]; edges: Edge[] } {
  const graph = projectGraph(document);
  return {
    nodes: graph.nodes.map((node) => {
      const participant = document.source.participants[node.participantKey];
      const agent = participant?.type === "agent" ? participant : undefined;
      return {
        id: node.id,
        type: "flowNode",
        position: {
          x: FLOW_LAYOUT_MARGIN + (node.position.y / 180) * (FLOW_NODE_WIDTH + FLOW_LAYOUT_NODE_SEPARATION),
          y: FLOW_LAYOUT_MARGIN + (node.position.x / 320) * 220,
        },
        selected: selectedNodeId === node.id,
        deletable: false,
        data: {
          kind: node.kind,
          label: node.kind === "entry" ? "Entry" : node.participantKey,
          subtitle: node.kind === "entry" ? `${document.source.outgoing_call ? "Outgoing" : "Incoming"} · ${node.participantKey}` : participant?.description || agent?.prompt || (participant?.type === "human" ? participant.connection.service : ""),
          toolCount: Object.keys(agent?.tools ?? {}).length,
          variableCount: Object.keys(agent?.variable_permissions ?? {}).length,
          issueCount: issues[node.id] ?? 0,
          readOnly: document.readOnly,
        },
      };
    }),
    edges: graph.edges.map((edge) => ({ ...edge, type: "smoothstep", deletable: false, reconnectable: false,
      label: edge.locked ? undefined : "transfer", style: { stroke: "var(--muted-foreground)" },
      labelStyle: { fill: "var(--foreground)" }, labelBgStyle: { fill: "var(--background)" },
    })),
  };
}

export function canConnectParticipants(document: SourceDocument, source: string, target: string): boolean {
  const targetKey = target === "$entry" ? projectGraph(document).nodes[0]!.participantKey : target;
  return !document.readOnly && target !== "$entry" && source !== targetKey && document.source.participants[source]?.type === "agent" && isTransferDestination(document.source, targetKey);
}

export const flowFitViewOptions = { padding: 0.3, maxZoom: 0.85 };
