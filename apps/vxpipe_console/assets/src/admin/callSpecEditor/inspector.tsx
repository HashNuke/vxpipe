import type { ModelCatalog } from "../modelCatalog";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { FlowLevelInspector, type CallSettingsTab } from "./flow-level-inspector";
import { GenericNodeInspector } from "./generic-node-inspector";
import { projectGraph } from "./graph";
import { HumanInspector } from "./human-inspector";
import type { HumanInspectorTab } from "./human-inspector-tabs";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { useJsonDrafts } from "./json-drafts";
import { ParticipantSource } from "./participant-source";

type Props = InspectorProps & {
  catalog: ModelCatalog;
  lookups: EditorLookups;
  selectedNodeId?: string | null;
  tab?: string;
  onTabChange: (tab: string) => void;
  onRenamed: (key: string) => void;
  onRemoved: () => void;
};

/** Callpipe's inspector dispatch, using a projection of the source document. */
export function Inspector({ selectedNodeId, tab, onRenamed, onRemoved, ...props }: Props) {
  const { drafts } = useJsonDrafts();
  const graph = projectGraph(props.document);
  const node = graph.nodes.find((candidate) => candidate.id === selectedNodeId);
  const selectedByEntryKey = selectedNodeId === graph.nodes.find((candidate) => candidate.kind === "entry")?.participantKey;
  if (selectedNodeId && !node && drafts[`participant:${selectedNodeId}`]) {
    return <aside className="flex h-full min-h-0 flex-col"><ParticipantSource {...props} participantKey={selectedNodeId} heading={selectedByEntryKey ? "Unapplied participant edit" : "Participant removed"}>
      {selectedByEntryKey ? <p className="p-4 text-sm">This participant is now the call entry. Its connection is configured in Call settings.</p> : <GenericNodeInspector participantKey={selectedNodeId} />}
    </ParticipantSource></aside>;
  }
  if (!selectedNodeId || selectedNodeId === "$settings" || node?.kind === "entry" || selectedByEntryKey) return <FlowLevelInspector {...props}
    tab={member<CallSettingsTab>(tab, ["connection", "defaults", "variables", "media", "advanced"], "connection")} />;
  if (!node) return <GenericNodeInspector participantKey={selectedNodeId} />;
  if (node.kind === "agent") return <AgentInspector {...props} participantKey={node.participantKey} onRenamed={onRenamed} onRemoved={onRemoved}
    tab={member<AgentInspectorTab>(tab, ["prompt", "voice", "variables", "transfers", "tools", "presence"], "prompt")} />;
  return <HumanInspector {...props} participantKey={node.participantKey} onRenamed={onRenamed} onRemoved={onRemoved}
    tab={member<HumanInspectorTab>(tab, ["connection", "voice", "presence"], "connection")} />;
}

function member<T extends string>(value: string | undefined, choices: readonly T[], fallback: T): T {
  return choices.find((choice) => choice === value) ?? fallback;
}
