import { useRef } from "react";
import { Copy, Download } from "lucide-react";
import { Button } from "../components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "../components/ui/sheet";
import { Textarea } from "../components/ui/textarea";
import type { ActionFeedback } from "./errorPresentation";
import type { CallSpecSource } from "./types";
export function SourceView({ open, onOpenChange, source, onFeedback }: { open: boolean; onOpenChange: (open: boolean) => void; source: CallSpecSource; onFeedback: (feedback: ActionFeedback) => void }) {
  const opener = useRef<HTMLElement | null>(null);
  const text = JSON.stringify(source, null, 2);
  async function copy() {
    try { await navigator.clipboard.writeText(text); onFeedback({ tone: "success", persistent: false, message: "Copied call spec JSON" }); }
    catch { onFeedback({ tone: "error", persistent: true, message: "Couldn't copy JSON. Select the text and copy it manually." }); }
  }
  function download() {
    let url: string | undefined;
    try {
      url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
      const link = document.createElement("a"); link.href = url; link.download = "call-spec.json"; link.click();
    } catch { onFeedback({ tone: "error", persistent: true, message: "Couldn't download JSON. Try copying it instead." }); }
    finally { if (url) URL.revokeObjectURL(url); }
  }
  return <Sheet modal={false} open={open} onOpenChange={onOpenChange}><SheetContent className="w-full sm:max-w-2xl" onOpenAutoFocus={() => { opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null; }} onCloseAutoFocus={(event) => { event.preventDefault(); opener.current?.focus(); }}>
    <SheetHeader><SheetTitle>Call spec source</SheetTitle><SheetDescription>Read-only JSON for the current call spec, including unsaved edits.</SheetDescription></SheetHeader>
    <div className="flex flex-wrap gap-2 px-4"><Button variant="outline" size="sm" onClick={() => void copy()}><Copy className="h-4 w-4" />Copy JSON</Button><Button variant="outline" size="sm" onClick={download}><Download className="h-4 w-4" />Download JSON</Button></div>
    <div className="min-h-0 flex-1 p-4 pt-0"><Textarea aria-label="Call spec JSON" readOnly value={text} spellCheck={false} className="h-full field-sizing-fixed resize-none font-mono text-xs" /></div>
  </SheetContent></Sheet>;
}
