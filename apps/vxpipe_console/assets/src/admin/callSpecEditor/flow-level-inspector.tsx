import { useLayoutEffect, useRef, useState } from "react";
import { FileText } from "lucide-react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "../components/ui/tabs";
import type { ModelCatalog } from "../modelCatalog";
import { IssueCount } from "./issue-count";
import { issueCounts } from "./issues";
import { InspectorIssues, UnplacedIssues } from "./issue-scope";
import { DefaultsPanel } from "./defaults-panel";
import { VariablesPanel } from "./variables-panel";
import { MediaPolicyFields } from "./media-policy-fields";
import { WaitSoundsPanel } from "./wait-sounds-panel";
import { AdvancedPanel } from "./advanced-panel";
import type { InspectorProps } from "./inspectorTypes";

const flowTabs = [
  { id: "defaults", label: "Models" },
  { id: "variables", label: "Variables" }, { id: "media", label: "Media" },
  { id: "wait", label: "Wait sounds" }, { id: "advanced", label: "Advanced" },
] as const;
export type CallSettingsTab = typeof flowTabs[number]["id"];

export function FlowLevelInspector({ catalog, tab, onTabChange, ...props }: InspectorProps & { catalog: ModelCatalog; tab?: CallSettingsTab; onTabChange?: (tab: CallSettingsTab) => void }) {
  const [activeTab, setActiveTab] = useState<CallSettingsTab>("defaults");
  const tabBar = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    tabBar.current?.querySelector<HTMLElement>('[role="tab"][data-state="active"]')?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }, [tab, activeTab]);
  const counts = issueCounts(props.document.source, props.issues ?? []).tabs.$settings ?? {};
  return <InspectorIssues source={props.document.source} issues={props.issues} request={props.focusRequest} nodeId="$settings" tab={tab ?? activeTab}><aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-background">
    <div className="shrink-0 p-4 pb-2"><div className="flex items-center gap-2 text-sm font-semibold text-foreground"><FileText className="h-4 w-4 text-muted-foreground" /><h2>Call settings</h2><span className="ml-auto text-xs font-normal text-muted-foreground">{props.document.source.outgoing_call ? "Outgoing call" : "Incoming call"}</span></div></div>
    <Tabs value={tab ?? activeTab} onValueChange={(next) => { setActiveTab(next as CallSettingsTab); onTabChange?.(next as CallSettingsTab); }} className="min-h-0 flex-1 gap-0">
      <div ref={tabBar} className="shrink-0 overflow-x-auto border-b border-border px-4 py-3">
        <TabsList aria-label="Call settings tabs" className="w-max">
          {flowTabs.map((item) => <TabsTrigger key={item.id} value={item.id} className="flex-none" aria-description={counts[item.id] ? `${counts[item.id]} ${counts[item.id] === 1 ? "issue" : "issues"}` : undefined}>{item.label}<IssueCount count={counts[item.id]} /></TabsTrigger>)}
        </TabsList>
      </div>
      {flowTabs.map((item) => <TabsContent key={item.id} value={item.id} className="m-0 min-h-0 flex-1 overflow-auto p-4">
        <UnplacedIssues />{item.id === "defaults" ? <DefaultsPanel {...props} catalog={catalog} />
          : item.id === "variables" ? <VariablesPanel {...props} />
          : item.id === "media" ? <MediaPolicyFields {...props} participantKey={null} />
          : item.id === "wait" ? <WaitSoundsPanel {...props} /> : <AdvancedPanel {...props} />}
      </TabsContent>)}
    </Tabs>
  </aside></InspectorIssues>;
}
