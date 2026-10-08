import { useState, type ReactNode } from "react";
import type { InspectorProps } from "./inspectorTypes";
import { IssueCount } from "./issue-count";
import { issueCounts } from "./issues";
import { InspectorIssues, UnplacedIssues } from "./issue-scope";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";

export type HumanInspectorTab = "connection" | "voice" | "presence";
export function HumanInspectorTabs({ connection, voice, presence, tab, onTabChange, document, issues, focusRequest, nodeId }: Pick<InspectorProps, "document" | "issues" | "focusRequest"> & { nodeId: string; connection: ReactNode; voice: ReactNode; presence: ReactNode; tab?: HumanInspectorTab; onTabChange?: (tab: HumanInspectorTab) => void }) {
  const [active, setActive] = useState<HumanInspectorTab>("connection");
  const counts = issueCounts(document.source, issues ?? []).tabs[nodeId] ?? {};
  return <InspectorIssues source={document.source} issues={issues} request={focusRequest} nodeId={nodeId} tab={tab ?? active}><Tabs value={tab ?? active} onValueChange={(value) => { setActive(value as HumanInspectorTab); onTabChange?.(value as HumanInspectorTab); }} className="min-h-0 flex-1 gap-0">
    <div className="shrink-0 overflow-x-auto border-b px-4"><TabsList variant="line" aria-label="Participant settings tabs" className="h-auto justify-start gap-1 rounded-none bg-transparent p-0">
      {(["connection", "voice", "presence"] as const).map((key) => <TabsTrigger key={key} value={key} aria-description={counts[key] ? `${counts[key]} ${counts[key] === 1 ? "issue" : "issues"}` : undefined} className="rounded-none px-3 py-3 text-sm after:bottom-0">{key === "connection" ? "Connection" : key === "voice" ? "Voice and model" : "Presence"}<IssueCount count={counts[key]} /></TabsTrigger>)}
    </TabsList></div>
    <TabsContent value="connection" className="m-0 min-h-0 flex-1 overflow-auto p-4"><UnplacedIssues />{connection}</TabsContent>
    <TabsContent value="voice" className="m-0 min-h-0 flex-1 overflow-auto p-4"><UnplacedIssues />{voice}</TabsContent>
    <TabsContent value="presence" className="m-0 min-h-0 flex-1 overflow-auto p-4"><UnplacedIssues />{presence}</TabsContent>
  </Tabs></InspectorIssues>;
}
