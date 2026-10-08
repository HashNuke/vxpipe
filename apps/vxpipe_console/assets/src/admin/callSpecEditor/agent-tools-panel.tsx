import { Fragment, useState } from "react";
import { KeyRound, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Item, ItemActions, ItemContent, ItemDescription, ItemGroup, ItemMedia, ItemSeparator, ItemTitle } from "../components/ui/item";
import { useIssueRequest } from "./issue-context";
import { IssueAnchor } from "./issue-anchor";
import { AddToolsModal } from "./add-tools-modal";
import { agent, setTools } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

export function AgentToolsPanel({ participantKey, integrations, ...props }: InspectorProps & { participantKey: string; integrations: string[] }) {
  const [editing, setEditing] = useState<{ name?: string } | null>(null);
  const request = useIssueRequest();
  const [dismissedRequest, setDismissedRequest] = useState<number>();
  const tools = agent(props.document.source, participantKey).tools ?? {};
  const requestedName = request?.path[0] === "participants" && request.path[1] === participantKey && request.path[2] === "tools" ? request.path[3] : undefined;
  const revealed = request && request.id !== dismissedRequest && requestedName && Object.hasOwn(tools, requestedName) ? { name: requestedName } : null;
  const selected = editing ?? revealed;
  return <div className="space-y-4">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-medium">Enabled tools</h3><Button variant="secondary" size="sm" disabled={props.document.readOnly} onClick={() => setEditing({})}><Plus className="h-4 w-4" />Add tool</Button></div>
    <ItemGroup className="rounded-md border border-border/60">{Object.entries(tools).map(([name, tool], index) => <Fragment key={name}>
      {index > 0 && <ItemSeparator />}<IssueAnchor path={["participants", participantKey, "tools", name]} issues={props.issues}><Item size="sm">
        <ItemMedia variant="icon"><KeyRound /></ItemMedia><ItemContent><ItemTitle className="wrap-anywhere">{name}</ItemTitle><ItemDescription className="wrap-anywhere">{tool.type} · {tool.integration ? `${tool.integration} · ` : ""}{tool.tool}<br />{tool.conversation_mode === "non_blocking" ? "Non-blocking" : tool.conversation_mode === "blocking" ? "Blocking" : "Default (blocking)"}</ItemDescription></ItemContent>
        <ItemActions><Button variant="ghost" size="icon-sm" aria-label={`Edit ${name}`} disabled={props.document.readOnly} onClick={() => setEditing({ name })}><Pencil className="h-4 w-4" /></Button><Button variant="ghost" size="icon-sm" aria-label={`Remove ${name}`} disabled={props.document.readOnly} onClick={() => props.onChange(setTools(props.document, participantKey, Object.fromEntries(Object.entries(tools).filter(([key]) => key !== name))))}><Trash2 className="h-4 w-4" /></Button></ItemActions>
      </Item></IssueAnchor>
    </Fragment>)}{!Object.keys(tools).length && <Item size="sm"><ItemContent><ItemDescription>No tools enabled for this agent.</ItemDescription></ItemContent></Item>}</ItemGroup>
    {selected && <AddToolsModal key={`${selected.name ?? "new"}:${request?.id ?? "manual"}`} {...props} participantKey={participantKey} previousName={selected.name} integrations={integrations} onClose={() => { setEditing(null); setDismissedRequest(request?.id); }} />}
  </div>;
}
