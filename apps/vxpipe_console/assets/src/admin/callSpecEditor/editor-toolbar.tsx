import { Bot, Handshake, Workflow } from "lucide-react"

import { Button } from "../components/ui/button"

export function FlowEditorToolbar({ onAddNode, onArrangeNodes, readOnly = false }: {
  onAddNode: (kind: "agent" | "human") => void;
  onArrangeNodes: () => void;
  readOnly?: boolean;
}) {
  return (
    <div
      data-flow-editor-toolbar
      role="toolbar"
      aria-label={"Add participants"}
      aria-orientation="horizontal"
      className="absolute bottom-4 left-1/2 z-10 flex w-max max-w-[calc(100vw-1rem)] -translate-x-1/2 flex-nowrap items-center justify-start gap-1.5 overflow-x-auto rounded-md border border-border bg-background p-2 shadow-lg  lg:right-[calc(34rem+0.75rem)] lg:left-[calc((100%-34rem)/2)] lg:max-w-[calc(100vw-35rem)]"
    >
      <div role="group" aria-label={"Add participants"} className="flex shrink-0 items-center gap-1 rounded-sm bg-muted p-1">
        <span className="px-1.5 text-xs font-medium text-muted-foreground">{"Add"}</span>
        <Button variant="secondary" size="sm" className="h-8 justify-center border-border bg-secondary text-secondary-foreground hover:bg-accent px-3" disabled={readOnly} onClick={() => onAddNode("agent")} aria-label={"Add agent"}>
          <Bot className="h-4 w-4" />
          Agent
        </Button>
        <Button variant="secondary" size="sm" className="h-8 justify-center border-border bg-secondary text-secondary-foreground hover:bg-accent px-3" disabled={readOnly} onClick={() => onAddNode("human")} aria-label={"Add human"}>
          <Handshake className="h-4 w-4" />
          Human
        </Button>
      </div>
      <Button variant="secondary" size="sm" className="h-8 justify-center border-border bg-secondary text-secondary-foreground hover:bg-accent px-3" onClick={onArrangeNodes} aria-label={"Arrange nodes"}>
        <Workflow className="h-4 w-4" />
        Arrange
      </Button>
    </div>
  )
}
