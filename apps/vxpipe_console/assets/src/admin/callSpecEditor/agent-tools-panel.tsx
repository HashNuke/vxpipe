import { Fragment, useState } from "react";
import { RotateCwFadingClock, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Item, ItemActions, ItemContent, ItemDescription, ItemGroup, ItemSeparator, ItemTitle } from "../components/ui/item";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../components/ui/tooltip";
import { useIssueRequest } from "./issue-context";
import { IssueAnchor } from "./issue-anchor";
import { AddToolsModal } from "./add-tools-modal";
import { EditToolModal } from "./edit-tool-modal";
import { agent, setTools } from "./edits";
import type { InspectorProps, ToolCatalog } from "./inspectorTypes";

export function AgentToolsPanel({ participantKey, integrations, catalog, ...props }: InspectorProps & { participantKey: string; integrations: string[]; catalog?: ToolCatalog }) {
  const [editing, setEditing] = useState<{ name?: string } | null>(null);
  const request = useIssueRequest();
  const [dismissedRequest, setDismissedRequest] = useState<number>();
  const tools = agent(props.document.source, participantKey).tools ?? {};
  const requestedName = request?.path[0] === "participants" && request.path[1] === participantKey && request.path[2] === "tools" ? request.path[3] : undefined;
  const revealed = request && request.id !== dismissedRequest && requestedName && Object.hasOwn(tools, requestedName) ? { name: requestedName } : null;
  const selected = editing ?? revealed;
  const close = () => { setEditing(null); setDismissedRequest(request?.id); };
  return <TooltipProvider><div className="space-y-4">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-medium">Enabled tools</h3><Button variant="secondary" size="sm" disabled={props.document.readOnly} onClick={() => setEditing({})}><Plus className="h-4 w-4" />Add tool</Button></div>
    <ItemGroup className="rounded-md border border-border/60">{Object.entries(tools).map(([name, tool], index) => <Fragment key={name}>
      {index > 0 && <ItemSeparator />}<IssueAnchor path={["participants", participantKey, "tools", name]} issues={props.issues}><Item size="sm">
        <ItemContent className="min-w-0"><ItemTitle className="max-w-full gap-1.5"><span className="min-w-0 wrap-anywhere">{tool.type} · {name}</span>{tool.conversation_mode !== "non_blocking" && <Tooltip><TooltipTrigger asChild><button type="button" aria-label={`${name}: Blocking`} className="inline-flex size-6 shrink-0 cursor-help items-center justify-center rounded-sm text-muted-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"><RotateCwFadingClock aria-hidden className="size-4" /></button></TooltipTrigger><TooltipContent side="top" sideOffset={4}>Blocking</TooltipContent></Tooltip>}</ItemTitle></ItemContent>
        <ItemActions><Button variant="ghost" size="icon-sm" aria-label={`Edit ${name}`} disabled={props.document.readOnly} onClick={() => setEditing({ name })}><Pencil className="h-4 w-4" /></Button><Button variant="ghost" size="icon-sm" aria-label={`Remove ${name}`} disabled={props.document.readOnly} onClick={() => props.onChange(setTools(props.document, participantKey, Object.fromEntries(Object.entries(tools).filter(([key]) => key !== name))))}><Trash2 className="h-4 w-4" /></Button></ItemActions>
      </Item></IssueAnchor>
    </Fragment>)}{!Object.keys(tools).length && <Item size="sm"><ItemContent><ItemDescription>No tools enabled for this agent.</ItemDescription></ItemContent></Item>}</ItemGroup>
    {selected && (selected.name !== undefined ? <EditToolModal key={`${selected.name}:${request?.id ?? "manual"}`} {...props} participantKey={participantKey} name={selected.name} onClose={close} /> : <AddToolsModal {...props} participantKey={participantKey} integrations={integrations} catalog={catalog} onClose={close} />)}
  </div></TooltipProvider>;
}
