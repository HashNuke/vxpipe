import { useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Checkbox } from "../components/ui/checkbox";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { ChoiceField } from "./editor-fields";
import { agent } from "./edits";
import type { AvailableTool, InspectorProps, ToolCatalog } from "./inspectorTypes";
import { IssueAnchor } from "./issue-anchor";
import { addTools, registeredToolName, registeredToolNameIssue, toolIdentity } from "./tool-edits";
import { McpToolChecklist, ToolPicker, ToolSearch } from "./tool-picker";
import type { ToolSelection } from "./types";
import { useActionFailure } from "./action-failure-context";

const emptyCatalog: ToolCatalog = { tools: [], mcpAvailable: false };
export function AddToolsModal({ document, onChange, issues, participantKey, integrations, catalog = emptyCatalog, onClose }: InspectorProps & { participantKey: string; integrations: string[]; catalog?: ToolCatalog; onClose: () => void }) {
  const tools = agent(document.source, participantKey).tools ?? {};
  const [selected, setSelected] = useState<AvailableTool[]>([]);
  const [integration, setIntegration] = useState<string>();
  const [search, setSearch] = useState("");
  const [toolModes, setToolModes] = useState<Record<string, "blocking" | "non_blocking">>({});
  const [error, setError] = useState("");
  const reportFailure = useActionFailure();
  const path = ["participants", participantKey, "tools", ""];
  const single = integration === undefined ? selected[0] : undefined;
  const toolMode = (tool: AvailableTool) => toolModes[toolIdentity(tool)] ?? "blocking";
  function unavailable(tool: AvailableTool) {
    if (Object.values(tools).some((entry) => toolIdentity(entry) === toolIdentity(tool))) return "Added";
    const name = registeredToolName(tool);
    const issue = tool.type === "mcp" ? registeredToolNameIssue(name) : undefined;
    if (issue) return issue;
    if (Object.hasOwn(tools, name)) return "Name in use";
  }
  function reset() { setSelected([]); setIntegration(undefined); setSearch(""); setError(""); }
  function toggle(tool: AvailableTool) {
    setSelected((current) => current.some((entry) => toolIdentity(entry) === toolIdentity(tool)) ? current.filter((entry) => toolIdentity(entry) !== toolIdentity(tool)) : [...current, tool]);
    setError("");
  }
  function submit() {
    try {
      const selections: ToolSelection[] = selected.map((entry) => ({ type: entry.type, tool: entry.tool, ...(entry.type === "mcp" ? { integration: entry.integration } : {}), ...(toolMode(entry) === "non_blocking" ? { conversation_mode: "non_blocking" as const } : {}) }));
      if (!selections.length) return;
      onChange(addTools(document, participantKey, selections));
      onClose();
    } catch (error) { setError(error instanceof Error ? error.message : "These tools could not be saved."); reportFailure("Couldn't save these tools. Your selection is still here."); }
  }
  const mcpTools = catalog.tools.filter((tool) => tool.type === "mcp" && tool.integration === integration);
  const enabled = mcpTools.filter((tool) => unavailable(tool) === "Added");
  const addable = mcpTools.filter((tool) => !unavailable(tool));
  const included = enabled.length + selected.length;
  const allChecked = enabled.length + addable.length > 0 && addable.every((tool) => selected.some((entry) => toolIdentity(entry) === toolIdentity(tool)));
  const action = integration ? selected.length ? `Add ${selected.length} ${selected.length === 1 ? "tool" : "tools"}` : "Add tools" : "Add tool";
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="flex h-[min(44rem,calc(100dvh-2rem))] flex-col gap-0 overflow-hidden p-0 sm:max-w-2xl">
    <DialogHeader className="shrink-0 px-5 pt-5 pb-4 text-left sm:px-6">
      <div className="flex min-h-8 items-center gap-2 pr-6">{(integration || single) && <Button variant="ghost" size="icon-sm" aria-label="All tools and MCPs" onClick={reset}><ArrowLeft className="size-4" /></Button>}<DialogTitle className="min-w-0 wrap-anywhere">{integration ? `Tools from ${integration}` : "Add tool"}</DialogTitle></div>
      <DialogDescription className="min-h-10 sm:min-h-5">{integration ? "Check the tools you want this agent to use." : "Choose a tool or explore an MCP integration."}</DialogDescription>
    </DialogHeader>
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 pb-4 sm:px-6">
      <IssueAnchor path={path} issues={issues} className="flex min-h-64 flex-1 flex-col gap-3 outline-none focus-visible:ring-2 focus-visible:ring-ring">
        {single ? <div className="min-h-0 flex-1 space-y-2 overflow-y-auto"><h3 className="wrap-anywhere text-sm font-medium">{single.tool}</h3><p className="wrap-anywhere text-xs text-muted-foreground">{single.integration ? `${single.integration} · MCP` : single.type === "platform" ? "Built-in tool" : "Host tool"}</p><p className="wrap-anywhere text-sm text-muted-foreground">{single.description}</p></div> : <>
          <div className="shrink-0"><ToolSearch key={integration ?? "catalog"} label={integration ? `Search ${integration} tools` : "Search tools and MCPs"} value={search} onChange={setSearch} /></div>
          {integration ? <>
            <div className="flex shrink-0 items-center justify-between gap-3 text-xs text-muted-foreground">
              <label className="flex cursor-pointer items-center gap-2 text-sm text-foreground"><Checkbox aria-label="Include all tools" disabled={document.readOnly || !addable.length} checked={allChecked ? true : included > 0 ? "indeterminate" : false} onCheckedChange={() => { setSelected(allChecked ? [] : addable); setError(""); }} />Include all tools</label>
              <span role="status" className="shrink-0">{selected.length} selected</span>
            </div>
            <p className="shrink-0 text-xs text-muted-foreground">Includes the tools available now. Future tools stay excluded.</p>
            {!catalog.mcpAvailable && <p role="status" className="shrink-0 text-sm text-muted-foreground">The MCP catalog is unavailable. Reload the editor to try again.</p>}
            <McpToolChecklist tools={mcpTools} search={search} selected={selected} unavailable={unavailable} disabled={document.readOnly} onToggle={toggle} nonBlocking={(tool) => toolMode(tool) === "non_blocking"} onNonBlocking={(tool, checked) => setToolModes((current) => ({ ...current, [toolIdentity(tool)]: checked ? "non_blocking" : "blocking" }))} />
          </> : <ToolPicker catalog={catalog} integrations={integrations} search={search} disabled={document.readOnly} unavailable={unavailable} onTool={(tool) => { setSelected([tool]); setError(""); }} onMcp={(name) => { setIntegration(name); setSelected([]); setSearch(""); setError(""); }} />}
        </>}
      </IssueAnchor>
      {single && <div className="shrink-0 border-t border-border pt-3"><ChoiceField label="Conversation mode" path={[...path, "conversation_mode"]} issues={issues} disabled={document.readOnly} value={toolMode(single)} choices={[{ value: "blocking", label: "Blocking" }, { value: "non_blocking", label: "Non-blocking" }]} onChange={(value) => setToolModes((current) => ({ ...current, [toolIdentity(single)]: value === "non_blocking" ? "non_blocking" : "blocking" }))} hint="Blocking waits for the result. Non-blocking lets the conversation continue while the tool runs." /></div>}
      {error && <p role="alert" className="shrink-0 text-sm text-destructive">{error}</p>}
    </div>
    <DialogFooter className="shrink-0 flex-row justify-end border-t border-border px-5 py-4 sm:px-6"><Button variant="outline" onClick={onClose}>Cancel</Button><Button className="min-w-28" disabled={document.readOnly || !selected.length} onClick={submit}>{action}</Button></DialogFooter>
  </DialogContent></Dialog>;
}
