import { ChevronRight, Search, Plug, Wrench } from "lucide-react";
import { Button } from "../components/ui/button";
import { Checkbox } from "../components/ui/checkbox";
import { Input } from "../components/ui/input";
import type { AvailableTool, ToolCatalog } from "./inspectorTypes";
import { toolIdentity } from "./tool-edits";

export function ToolSearch({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return <div className="relative"><Search aria-hidden className="pointer-events-none absolute top-2.5 left-3 size-4 text-muted-foreground" /><Input type="search" aria-label={label} placeholder={label} value={value} onChange={(event) => onChange(event.target.value)} className="pl-9" /></div>;
}
const matches = (query: string, ...values: string[]) => values.join(" ").toLowerCase().includes(query.trim().toLowerCase());
const rowClass = "h-auto min-h-14 w-full justify-start gap-3 rounded-none px-3 py-3 text-left whitespace-normal";

type PickerProps = { catalog: ToolCatalog; integrations: string[]; search: string; disabled: boolean; unavailable: (tool: AvailableTool) => string | undefined; onTool: (tool: AvailableTool) => void; onMcp: (integration: string) => void };
export function ToolPicker({ catalog, integrations, search, disabled, unavailable, onTool, onMcp }: PickerProps) {
  const mcps = [...new Set([...integrations, ...catalog.tools.flatMap((tool) => tool.integration ? [tool.integration] : [])])].sort();
  const shownMcps = mcps.filter((name) => matches(search, name, "MCP"));
  const local = catalog.tools.filter((tool) => tool.type !== "mcp" && matches(search, tool.tool, tool.description, tool.type === "platform" ? "Built-in" : "Host"));
  return <div role="region" aria-label="Available tools and MCPs" tabIndex={0} className="min-h-0 flex-1 divide-y divide-border overflow-y-auto overscroll-contain rounded-md border border-border outline-none focus-visible:ring-2 focus-visible:ring-ring">
    {(["platform", "host"] as const).map((type) => {
      const tools = local.filter((tool) => tool.type === type);
      return tools.length > 0 && <section key={type} aria-label={type === "platform" ? "Built-in tools" : "Host tools"}><h3 className="sticky top-0 z-10 bg-muted px-3 py-2 text-xs font-medium text-muted-foreground">{type === "platform" ? "Built-in tools" : "Host tools"}</h3>{tools.map((tool) => <Button key={toolIdentity(tool)} variant="ghost" aria-label={tool.tool} disabled={disabled || !!unavailable(tool)} className={rowClass} onClick={() => onTool(tool)}>
        <Wrench className="size-4 shrink-0 text-muted-foreground" /><span className="min-w-0 flex-1"><span className="block wrap-anywhere font-medium">{tool.tool}</span><span className="mt-0.5 block wrap-anywhere text-xs font-normal text-muted-foreground">{tool.description}</span></span>{unavailable(tool) ? <span className="text-xs font-normal text-muted-foreground">{unavailable(tool)}</span> : <ChevronRight className="size-4 shrink-0 text-muted-foreground" />}
      </Button>)}</section>;
    })}
    {shownMcps.length > 0 && <section aria-label="MCP integrations"><h3 className="sticky top-0 z-10 bg-muted px-3 py-2 text-xs font-medium text-muted-foreground">MCP integrations</h3>{shownMcps.map((name) => {
      const count = catalog.tools.filter((tool) => tool.integration === name).length;
      return <Button key={name} variant="ghost" aria-label={name} disabled={disabled} className={rowClass} onClick={() => onMcp(name)}><Plug className="size-4 shrink-0 text-muted-foreground" /><span className="min-w-0 flex-1 wrap-anywhere font-medium">{name} <span className="font-normal whitespace-nowrap text-muted-foreground">({catalog.mcpAvailable ? count : "Catalog unavailable"})</span></span><ChevronRight className="size-4 shrink-0 text-muted-foreground" /></Button>;
    })}</section>}
    {!shownMcps.length && !local.length && <p className="px-4 py-8 text-center text-sm text-muted-foreground">{search ? "No tools or MCPs match your search." : "No tools are available. Configure a tool or MCP integration to get started."}</p>}
  </div>;
}

export function McpToolChecklist({ tools, search, selected, unavailable, disabled, onToggle, nonBlocking, onNonBlocking }: { tools: AvailableTool[]; search: string; selected: AvailableTool[]; unavailable: PickerProps["unavailable"]; disabled: boolean; onToggle: (tool: AvailableTool) => void; nonBlocking: (tool: AvailableTool) => boolean; onNonBlocking: (tool: AvailableTool, checked: boolean) => void }) {
  const shown = tools.filter((tool) => matches(search, tool.tool, tool.description));
  return <div role="region" aria-label="MCP tools" tabIndex={0} className="min-h-0 flex-1 divide-y divide-border overflow-y-auto overscroll-contain rounded-md border border-border outline-none focus-visible:ring-2 focus-visible:ring-ring">{shown.map((tool) => {
    const status = unavailable(tool);
    const checked = selected.some((entry) => toolIdentity(entry) === toolIdentity(tool));
    return <div key={toolIdentity(tool)} className="space-y-2 px-3 py-3 hover:bg-muted/50">
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <label className="flex min-h-6 min-w-40 flex-1 cursor-pointer items-center gap-3 text-sm font-medium"><Checkbox aria-label={tool.tool} disabled={disabled || !!status} checked={checked || status === "Added"} onCheckedChange={() => onToggle(tool)} /><span className="wrap-anywhere">{tool.tool}</span></label>
        {status ? <span className="text-xs text-muted-foreground">{status}</span> : <label className={`flex min-h-6 items-center gap-2 text-xs ${checked ? "cursor-pointer text-foreground" : "text-muted-foreground"}`}><Checkbox aria-label={`Non-blocking ${tool.tool}`} disabled={disabled || !checked} checked={nonBlocking(tool)} onCheckedChange={(value) => onNonBlocking(tool, value === true)} />Non-blocking</label>}
      </div>
      <p className="wrap-anywhere text-xs text-muted-foreground">{tool.description}</p>
    </div>;
  })}{!shown.length && <p className="px-4 py-8 text-center text-sm text-muted-foreground">{search ? "No tools match your search." : "No tools are available from this MCP. Check its connection and allowed tools, then reload the editor."}</p>}</div>;
}
