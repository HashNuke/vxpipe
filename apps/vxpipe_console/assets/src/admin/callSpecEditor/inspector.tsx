import type { ModelCatalog } from "../modelCatalog";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { FlowLevelInspector, type CallSettingsTab } from "./flow-level-inspector";
import { GenericNodeInspector } from "./generic-node-inspector";
import { projectGraph, type TransferEdge } from "./graph";
import { HumanInspector } from "./human-inspector";
import type { HumanInspectorTab } from "./human-inspector-tabs";
import { InboundInspector } from "./inbound-inspector";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { SelectedEdgeInspector } from "./selected-edge-inspector";

type Props = InspectorProps & {
  catalog: ModelCatalog;
  lookups: EditorLookups;
  selectedNodeId?: string | null;
  selectedEdgeId?: string | null;
  tab?: string;
  onTabChange: (tab: string) => void;
  onDeleteEdge: (edge: TransferEdge) => void;
  onRenamed: (key: string) => void;
  onRemoved: () => void;
};

/** Callpipe's inspector dispatch, using a projection of the source document. */
export function Inspector({ selectedNodeId, selectedEdgeId, tab, onDeleteEdge, onRenamed, onRemoved, ...props }: Props) {
  const graph = projectGraph(props.document);
  const edge = graph.edges.find((candidate) => candidate.id === selectedEdgeId);
  if (edge) return <SelectedEdgeInspector selectedEdge={edge} readOnly={props.document.readOnly} onDeleteEdge={onDeleteEdge} />;
  if (!selectedNodeId || selectedNodeId === "$settings") return <FlowLevelInspector {...props}
    tab={member<CallSettingsTab>(tab, ["direction", "defaults", "variables", "media", "wait", "advanced"], "direction")} />;
  const node = graph.nodes.find((candidate) => candidate.id === selectedNodeId);
  if (!node) return <GenericNodeInspector participantKey={selectedNodeId} />;
  if (node.kind === "entry") return <InboundInspector {...props} tab={member<HumanInspectorTab>(tab, ["connection", "voice", "presence"], "connection")} />;
  if (node.kind === "agent") return <AgentInspector {...props} participantKey={node.participantKey} onRenamed={onRenamed} onRemoved={onRemoved}
    tab={member<AgentInspectorTab>(tab, ["prompt", "voice", "variables", "transfers", "tools", "presence"], "prompt")} />;
  return <HumanInspector {...props} participantKey={node.participantKey} onRenamed={onRenamed} onRemoved={onRemoved}
    tab={member<HumanInspectorTab>(tab, ["connection", "voice", "presence"], "connection")} />;
}

function member<T extends string>(value: string | undefined, choices: readonly T[], fallback: T): T {
  return choices.find((choice) => choice === value) ?? fallback;
}
