import { useState, useSyncExternalStore, type ReactNode } from "react";
import { Settings } from "lucide-react";
import { FlowEditorHeader, type EditorHeaderProps } from "./editor-header";
import { FlowEditorToolbar } from "./editor-toolbar";
import { FlowCanvas, type FlowCanvasProps } from "./flow-canvas";
import { Button } from "../components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "../components/ui/sheet";

function subscribeViewport(callback: () => void) {
  window.addEventListener("resize", callback);
  return () => window.removeEventListener("resize", callback);
}
const narrowViewport = () => window.innerWidth < 1024;
const serverViewport = () => false;

type Props = FlowCanvasProps & Omit<EditorHeaderProps, "flowName" | "readOnly"> & {
  inspector: ReactNode;
  inspectorTitle: string;
  onAddNode: (kind: "agent" | "human") => void;
};

/** Canvas/sidebar geometry copied from Callpipe, with a standard Sheet on phones. */
export function FlowEditorLayout({ document, selectedNodeId, issues, onConnect, onSelectNode, onSelectEdge, inspector, inspectorTitle, onAddNode, ...header }: Props) {
  const [arrangement, setArrangement] = useState(0);
  const [inspectorOpen, setInspectorOpen] = useState(false);
  const narrow = useSyncExternalStore(subscribeViewport, narrowViewport, serverViewport);
  function selectNode(id: string | null) { onSelectNode(id); if (narrow) setInspectorOpen(true); }
  function selectEdge(id: string) { onSelectEdge(id); if (narrow) setInspectorOpen(true); }
  return (
    <main className="relative h-dvh min-h-0 overflow-hidden overscroll-none bg-muted">
      {header.loading && <div role="status" className="absolute inset-0 z-20 grid place-items-center bg-background/80 text-sm font-medium text-muted-foreground">Loading call spec…</div>}
      <FlowCanvas key={arrangement} document={document} selectedNodeId={selectedNodeId} issues={issues} onConnect={onConnect} onSelectNode={selectNode} onSelectEdge={selectEdge} />
      <FlowEditorHeader {...header} flowName={document.source.name} readOnly={document.readOnly} />
      {document.notice && <p role="status" className="absolute left-4 right-4 top-44 z-10 rounded-md border bg-background p-3 text-sm lg:right-[35rem]">{document.notice}</p>}
      <div className="absolute bottom-24 left-4 z-10 lg:left-3">
        <Button variant="outline" onClick={() => selectNode(null)}><Settings className="h-4 w-4" />Call settings</Button>
      </div>
      <FlowEditorToolbar onAddNode={onAddNode} onArrangeNodes={() => setArrangement((value) => value + 1)} readOnly={document.readOnly || header.loading || header.saving || header.publishing} />
      {!narrow && <section aria-label={inspectorTitle} data-flow-editor-sidebar className="absolute inset-y-0 right-0 z-10 flex w-[34rem] min-h-0 flex-col overflow-auto border-l border-border bg-background/95 shadow-xl backdrop-blur">{inspector}</section>}
      {narrow && <Sheet open={inspectorOpen} onOpenChange={setInspectorOpen}><SheetContent className="w-full gap-0 overflow-y-auto pt-10 sm:max-w-[34rem]">
        <SheetHeader className="sr-only"><SheetTitle>{inspectorTitle}</SheetTitle><SheetDescription className="sr-only">Edit the selected call spec settings.</SheetDescription></SheetHeader>
        {inspector}
      </SheetContent></Sheet>}
    </main>
  );
}
