import { useState } from "react";
import { ArrowLeft, KeyRound } from "lucide-react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { ChoiceField, TextField } from "./editor-fields";
import { agent } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import { IssueAnchor } from "./issue-anchor";
import { useIssueRequest } from "./issue-context";
import { setTool } from "./tool-edits";
import type { ToolSelection } from "./types";
import { useActionFailure } from "./action-failure-context";

export function AddToolsModal({ document, onChange, issues, participantKey, previousName, integrations, onClose }: InspectorProps & { participantKey: string; previousName?: string; integrations: string[]; onClose: () => void }) {
  const tools = agent(document.source, participantKey).tools ?? {};
  const saved = previousName !== undefined && Object.hasOwn(tools, previousName) ? tools[previousName] : undefined;
  const requestedField = useIssueRequest()?.path.at(-1);
  const [step, setStep] = useState(saved ? requestedField === "tool" || requestedField === "integration" ? 1 : requestedField === "type" ? 0 : 2 : 0);
  const [type, setType] = useState<ToolSelection["type"]>(saved?.type ?? "host");
  const [tool, setToolName] = useState(saved?.tool ?? "");
  const [integration, setIntegration] = useState(saved?.integration ?? "");
  const [name, setName] = useState(previousName ?? "");
  const [mode, setMode] = useState(saved?.conversation_mode ?? "");
  const [error, setError] = useState("");
  const reportFailure = useActionFailure();
  const path = ["participants", participantKey, "tools", previousName ?? name];
  function chooseSource(type: ToolSelection["type"]) {
    setType(type); setToolName(""); setIntegration(""); setName(""); setError(""); setStep(1);
  }
  function submit() {
    try {
      const selection: ToolSelection = { type, tool, ...(type === "mcp" ? { integration } : {}), ...(mode ? { conversation_mode: mode as ToolSelection["conversation_mode"] } : {}) };
      onChange(setTool(document, participantKey, previousName, type === "host" ? tool : name, selection)); onClose();
    } catch (error) { setError(error instanceof Error ? error.message : "This tool could not be saved."); reportFailure("Couldn't save this tool. Check its name and options."); }
  }
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto sm:max-w-2xl">
    <DialogHeader><DialogTitle>{saved ? "Edit tool" : "Add tool"}</DialogTitle><DialogDescription>Choose a source, name its tool, then set how this agent uses it.</DialogDescription></DialogHeader>
    <div className="min-h-72 space-y-4">
      <div className="flex items-center gap-3">{step > 0 && <Button variant="ghost" size="sm" onClick={() => { setStep(step - 1); setError(""); }}><ArrowLeft className="h-4 w-4" />Back</Button>}<h3 className="text-sm font-semibold">{["1 · Source", "2 · Tool", "3 · Options"][step]}</h3></div>
      {step === 0 ? <IssueAnchor path={[...path, "type"]} issues={issues} className="space-y-2">{([
        ["host", "Host", "A tool registered by this Vxpipe installation."],
        ["mcp", "MCP", "A remote tool from a configured integration."],
        ["platform", "Platform", "A built-in Vxpipe tool."],
      ] as const).map(([type, title, description]) => <Button key={type} variant="outline" aria-label={title} disabled={document.readOnly} className="h-auto w-full justify-start gap-3 p-3 text-left" onClick={() => chooseSource(type)}>
        <KeyRound className="h-4 w-4 shrink-0 text-muted-foreground" /><span className="min-w-0 whitespace-normal"><span className="block text-sm font-semibold">{title}</span><span className="mt-1 block text-xs font-normal text-muted-foreground">{description}</span></span>
      </Button>)}</IssueAnchor> : step === 1 ? <fieldset disabled={document.readOnly} className="space-y-4">
        {type === "mcp" && <ChoiceField label="MCP integration" path={[...path, "integration"]} issues={issues} disabled={document.readOnly} value={integration} choices={[{ value: "", label: "Choose an integration" }, ...integrations.map((name) => ({ value: name, label: name }))]} onChange={setIntegration} />}
        {type === "mcp" && !integrations.length && <p className="text-xs text-muted-foreground">Configure an MCP integration before adding a remote tool.</p>}
        <TextField label="Tool name" path={[...path, "tool"]} issues={issues} disabled={document.readOnly} value={tool} onChange={setToolName}
          hint={type === "mcp" ? "Enter the tool name exposed by this integration." : type === "host" ? "Enter the registered host Action name." : "Enter the name of a built-in platform tool."} />
      </fieldset> : <fieldset disabled={document.readOnly} className="space-y-4">
        <p className="wrap-anywhere text-sm text-muted-foreground">{type}{type === "mcp" ? ` · ${integration}` : ""} · {tool}</p>
        <TextField label="Local tool key" path={path} issues={issues} disabled={document.readOnly || type === "host"} value={type === "host" ? tool : name} onChange={setName} hint={type === "host" ? "Host tools keep their registered name." : "The name this agent uses to call the tool. It must be unique for this agent."} />
        <ChoiceField label="Conversation mode" path={[...path, "conversation_mode"]} issues={issues} disabled={document.readOnly} value={mode} choices={[{ value: "", label: "Default (blocking)" }, { value: "blocking", label: "Blocking" }, { value: "non_blocking", label: "Non-blocking" }]} onChange={setMode}
          hint="Blocking waits for the result before continuing. Non-blocking lets the conversation continue while the tool runs." />
      </fieldset>}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </div>
    <DialogFooter><Button variant="outline" onClick={onClose}>Cancel</Button>{step === 1 ? <Button disabled={document.readOnly || !tool || (type === "mcp" && !integration)} onClick={() => { if (!name || type === "host") setName(tool); setStep(2); }}>Next</Button> : step === 2 && <Button disabled={document.readOnly} onClick={submit}>{saved ? "Save tool" : "Add tool"}</Button>}</DialogFooter>
  </DialogContent></Dialog>;
}
