import { Handle, Position } from "@xyflow/react"
import { Bot, CircleAlert, Handshake, PhoneIncoming, Variable, Wrench } from "lucide-react"

import { cn as cx } from "cn"
import type { FlowNodeData } from "./flow-layout"

const nodeTone = {
  entry: {
    icon: PhoneIncoming,
    iconClassName: "h-4 w-4",
    className: "border-primary/40 bg-accent text-accent-foreground",
    handle: "bg-primary"
  },
  agent: {
    icon: Bot,
    iconClassName: "h-5 w-5",
    className: "border-border bg-card text-card-foreground",
    handle: "bg-primary"
  },
  human: {
    icon: Handshake,
    iconClassName: "h-4 w-4",
    className: "border-border bg-card text-card-foreground",
    handle: "bg-primary"
  },
}

export function FlowNode({ data, selected }: { data: FlowNodeData; selected?: boolean }) {
  const tone = nodeTone[data.kind];
  const Icon = tone.icon;
  const hasInput = data.kind !== "entry";
  const hasOutput = data.kind !== "human";
  const showCapabilityBadges = data.kind === "agent";
  const subtitle = data.subtitle;
  const issues = data.issueCount;
  const showNodeIndicators = issues > 0;
  const label = data.label;
  const connectorClass = cx(
    "group h-7 w-7 rounded-full border-[3px] border-background bg-primary shadow-md ring-2 ring-primary transition hover:scale-125 hover:bg-background hover:ring-[3px] hover:ring-ring focus-visible:scale-125 focus-visible:bg-background focus-visible:ring-[3px] focus-visible:ring-ring before:absolute before:left-1/2 before:top-1/2 before:h-2.5 before:w-0.5 before:-translate-x-1/2 before:-translate-y-1/2 before:rounded-full before:bg-primary-foreground before:content-[''] after:absolute after:left-1/2 after:top-1/2 after:h-0.5 after:w-2.5 after:-translate-x-1/2 after:-translate-y-1/2 after:rounded-full after:bg-primary-foreground after:content-[''] hover:before:bg-primary hover:after:bg-primary focus-visible:before:bg-primary focus-visible:after:bg-primary",
    tone.handle,
    data.kind === "entry" && "h-2 w-2 border-0 before:hidden after:hidden"
  )

  return (
    <div
      className={cx(
        "relative w-80 rounded-md border bg-background p-3 shadow-sm transition",
        tone.className,
        selected && "ring-2 ring-ring ring-offset-2 ring-offset-background"
      )}
    >
      {hasInput && (
        <Handle
          type="target"
          isConnectable={!data.readOnly && data.kind !== "entry"}
          aria-label={`Transfer to ${label}`}
          position={Position.Top}
          className={connectorClass}
        />
      )}
      <div
        data-flow-node-content
        className={cx("flex gap-3", subtitle ? "items-start" : "items-center")}
      >
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-current/15 bg-background/75">
          <Icon className={tone.iconClassName} />
        </div>
        <div className="min-w-0 flex-1">
          <div data-flow-node-title-row className="flex min-w-0 items-center gap-2">
            <div className="min-w-0 flex-1 truncate text-sm font-semibold">{label}</div>
            {showNodeIndicators && (
              <div className="flex shrink-0 items-center gap-1 text-[11px] font-medium">
                {issues > 0 && (
                  <span aria-label={`${issues} ${issues === 1 ? "issue" : "issues"}`} className="inline-flex items-center gap-1 rounded-sm bg-destructive/10 px-1.5 py-0.5 text-destructive ring-1 ring-destructive/30">
                    <CircleAlert className="h-3 w-3" />
                    {issues}
                  </span>
                )}
              </div>
            )}
          </div>
          {subtitle && <div className="mt-0.5 line-clamp-2 text-xs opacity-75">{subtitle}</div>}
        </div>
      </div>
      {showCapabilityBadges && (
        <div className="mt-3 flex flex-wrap gap-2 text-xs">
          <span className="inline-flex items-center gap-1 rounded-sm bg-background/80 px-2 py-1 font-medium shadow-sm">
            <Wrench className="h-3 w-3" />
            {data.toolCount} {data.toolCount === 1 ? "tool" : "tools"}
          </span>
          <span className="inline-flex items-center gap-1 rounded-sm bg-background/80 px-2 py-1 font-medium shadow-sm">
            <Variable className="h-3 w-3" />
            {data.variableCount} {data.variableCount === 1 ? "section" : "sections"}
          </span>
        </div>
      )}
      {hasOutput && (
        <Handle
          type="source"
          isConnectable={!data.readOnly && data.kind !== "entry"}
          aria-label={`Transfer from ${label}`}
          position={Position.Bottom}
          className={connectorClass}
        />
      )}
    </div>
  )
}
