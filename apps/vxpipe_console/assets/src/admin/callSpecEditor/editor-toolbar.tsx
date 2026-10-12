import { Plus, Settings, Workflow } from "lucide-react"

import { Button } from "../components/ui/button"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../components/ui/tooltip"
import { IssueCount } from "./issue-count"

export function FlowEditorToolbar({ onAddNode, onArrangeNodes, onOpenCallSettings, settingsIssues = 0, readOnly = false }: {
  onAddNode: (kind: "agent" | "human") => void;
  onArrangeNodes: () => void;
  onOpenCallSettings: () => void;
  settingsIssues?: number;
  readOnly?: boolean;
}) {
  return (
    <TooltipProvider><div
      data-flow-editor-toolbar
      role="toolbar"
      aria-label={"Call spec tools"}
      aria-orientation="horizontal"
      className="flex min-w-0 items-stretch rounded-b-md border-t border-border bg-[color-mix(in_oklch,var(--background)_50%,var(--muted))] text-foreground"
    >
        <Button variant="ghost" size="sm" className="h-10 rounded-none rounded-bl-md px-2 text-foreground hover:bg-control-hover hover:text-foreground dark:hover:bg-control-hover focus-visible:ring-inset" disabled={readOnly} onClick={() => onAddNode("agent")} aria-label={"Add agent"}>
          <Plus className="h-4 w-4" />
          Add AI Agent
        </Button>
        <Button variant="ghost" size="sm" className="h-10 rounded-none px-2 text-foreground hover:bg-control-hover hover:text-foreground dark:hover:bg-control-hover focus-visible:ring-inset" disabled={readOnly} onClick={() => onAddNode("human")} aria-label={"Add human"}>
          <Plus className="h-4 w-4" />
          Add Human
        </Button>
      <Tooltip><TooltipTrigger asChild>
        <Button variant="ghost" size="icon" className="size-10 rounded-none text-foreground hover:bg-control-hover hover:text-foreground dark:hover:bg-control-hover focus-visible:ring-inset" onClick={onArrangeNodes} aria-label="Arrange nodes"><Workflow className="h-4 w-4" /></Button>
      </TooltipTrigger><TooltipContent side="top" sideOffset={8}>Arrange nodes</TooltipContent></Tooltip>
      <Tooltip><TooltipTrigger asChild>
        <Button variant="ghost" size="icon" className="relative ml-auto size-10 rounded-none rounded-br-md text-foreground hover:bg-control-hover hover:text-foreground dark:hover:bg-control-hover focus-visible:ring-inset" onClick={onOpenCallSettings} aria-label="Call settings" aria-description={settingsIssues ? `${settingsIssues} ${settingsIssues === 1 ? "issue" : "issues"}` : undefined}>
          <Settings className="h-4 w-4" /><span className="pointer-events-none absolute right-0.5 top-0.5"><IssueCount count={settingsIssues} /></span>
        </Button>
      </TooltipTrigger><TooltipContent side="top" sideOffset={8}>Call settings</TooltipContent></Tooltip>
    </div></TooltipProvider>
  )
}
