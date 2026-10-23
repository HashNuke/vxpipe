import { useState } from "react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { useActionFailure } from "./action-failure-context";
import { ChoiceField } from "./editor-fields";
import { agent } from "./edits";
import { IssueAnchor } from "./issue-anchor";
import { setTool } from "./tool-edits";
import type { InspectorProps } from "./inspectorTypes";

export function EditToolModal({ document, onChange, issues, participantKey, name, onClose }: InspectorProps & { participantKey: string; name: string; onClose: () => void }) {
  const saved = agent(document.source, participantKey).tools?.[name];
  const [mode, setMode] = useState(saved?.conversation_mode ?? "blocking");
  const [error, setError] = useState("");
  const reportFailure = useActionFailure();
  const path = ["participants", participantKey, "tools", name];
  function submit() {
    try {
      if (!saved) throw new Error("That tool no longer exists.");
      const selection = { ...saved };
      if (mode !== (saved.conversation_mode ?? "blocking")) {
        if (mode === "blocking") delete selection.conversation_mode;
        else selection.conversation_mode = mode;
      }
      onChange(setTool(document, participantKey, name, name, selection));
      onClose();
    } catch (error) {
      setError(error instanceof Error ? error.message : "This tool could not be saved.");
      reportFailure("Couldn't save this tool. Your changes are still here.");
    }
  }
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="sm:max-w-md">
    <DialogHeader className="text-left"><DialogTitle>Edit tool</DialogTitle><DialogDescription className="wrap-anywhere">{saved?.type === "mcp" ? `${saved.integration} · ${saved.tool}` : saved?.tool ?? name}</DialogDescription></DialogHeader>
    <IssueAnchor path={path} issues={issues}>
      <ChoiceField label="Conversation mode" path={[...path, "conversation_mode"]} issues={issues} disabled={document.readOnly} value={mode}
        choices={[{ value: "blocking", label: "Blocking" }, { value: "non_blocking", label: "Non-blocking" }]} onChange={(value) => setMode(value === "non_blocking" ? "non_blocking" : "blocking")}
        hint="Blocking waits for the result. Non-blocking lets the conversation continue while the tool runs." />
    </IssueAnchor>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <DialogFooter className="flex-row justify-end"><Button variant="outline" onClick={onClose}>Cancel</Button><Button disabled={document.readOnly || !saved} onClick={submit}>Save tool</Button></DialogFooter>
  </DialogContent></Dialog>;
}
