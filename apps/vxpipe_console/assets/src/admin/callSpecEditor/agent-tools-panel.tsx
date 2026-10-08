import { Fragment, useState } from "react";
import { KeyRound, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Item, ItemActions, ItemContent, ItemDescription, ItemGroup, ItemMedia, ItemSeparator, ItemTitle } from "../components/ui/item";
import { AddToolsModal } from "./add-tools-modal";
import { agent, setTools } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

export function AgentToolsPanel({ participantKey, integrations, ...props }: InspectorProps & { participantKey: string; integrations: string[] }) {
  const [editing, setEditing] = useState<{ name?: string } | null>(null);
  const tools = agent(props.document.source, participantKey).tools ?? {};
  return <div className="space-y-4">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-medium">Enabled tools</h3><Button variant="secondary" size="sm" disabled={props.document.readOnly} onClick={() => setEditing({})}><Plus className="h-4 w-4" />Add tool</Button></div>
    <ItemGroup className="rounded-md border border-border/60">{Object.entries(tools).map(([name, tool], index) => <Fragment key={name}>
      {index > 0 && <ItemSeparator />}<Item size="sm" data-field-path={JSON.stringify(["participants", participantKey, "tools", name])}>
        <ItemMedia variant="icon"><KeyRound /></ItemMedia><ItemContent><ItemTitle className="wrap-anywhere">{name}</ItemTitle><ItemDescription className="wrap-anywhere">{tool.type} · {tool.integration ? `${tool.integration} · ` : ""}{tool.tool}<br />{tool.conversation_mode === "non_blocking" ? "Non-blocking" : tool.conversation_mode === "blocking" ? "Blocking" : "Default (blocking)"}</ItemDescription></ItemContent>
        <ItemActions><Button variant="ghost" size="icon-sm" aria-label={`Edit ${name}`} disabled={props.document.readOnly} onClick={() => setEditing({ name })}><Pencil className="h-4 w-4" /></Button><Button variant="ghost" size="icon-sm" aria-label={`Remove ${name}`} disabled={props.document.readOnly} onClick={() => props.onChange(setTools(props.document, participantKey, Object.fromEntries(Object.entries(tools).filter(([key]) => key !== name))))}><Trash2 className="h-4 w-4" /></Button></ItemActions>
      </Item>
    </Fragment>)}{!Object.keys(tools).length && <Item size="sm"><ItemContent><ItemDescription>No tools enabled for this agent.</ItemDescription></ItemContent></Item>}</ItemGroup>
    {editing && <AddToolsModal {...props} participantKey={participantKey} previousName={editing.name} integrations={integrations} onClose={() => setEditing(null)} />}
  </div>;
}
