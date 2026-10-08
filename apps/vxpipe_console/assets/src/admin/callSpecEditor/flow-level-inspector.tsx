import { useLayoutEffect, useRef, useState } from "react";
import { FileText } from "lucide-react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "../components/ui/tabs";
import type { ModelCatalog } from "../modelCatalog";
import { DirectionPanel } from "./direction-panel";
import { DefaultsPanel } from "./defaults-panel";
import { VariablesPanel } from "./variables-panel";
import { MediaPolicyFields } from "./media-policy-fields";
import { WaitSoundsPanel } from "./wait-sounds-panel";
import { AdvancedPanel } from "./advanced-panel";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";

const flowTabs = [
  { id: "direction", label: "Direction" }, { id: "defaults", label: "Defaults" },
  { id: "variables", label: "Variables" }, { id: "media", label: "Media and recording" },
  { id: "wait", label: "Wait sounds" }, { id: "advanced", label: "Advanced" },
] as const;
export type CallSettingsTab = typeof flowTabs[number]["id"];

export function FlowLevelInspector({ catalog, lookups, tab, onTabChange, ...props }: InspectorProps & { catalog: ModelCatalog; lookups: EditorLookups; tab?: CallSettingsTab; onTabChange?: (tab: CallSettingsTab) => void }) {
  const [activeTab, setActiveTab] = useState<CallSettingsTab>("direction");
  const tabBar = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    tabBar.current?.querySelector<HTMLElement>('[role="tab"][data-state="active"]')?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }, [tab, activeTab]);
  return <aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-background">
    <div className="shrink-0 p-4 pb-2"><div className="flex items-center gap-2 text-sm font-semibold text-foreground"><FileText className="h-4 w-4 text-muted-foreground" /><span>Call settings</span></div></div>
    <Tabs value={tab ?? activeTab} onValueChange={(next) => { setActiveTab(next as CallSettingsTab); onTabChange?.(next as CallSettingsTab); }} className="min-h-0 flex-1 gap-0">
      <div ref={tabBar} className="shrink-0 overflow-x-auto border-b border-border px-4">
        <TabsList variant="line" aria-label="Call settings tabs" className="h-auto justify-start gap-1 rounded-none bg-transparent p-0">
          {flowTabs.map((item) => <TabsTrigger key={item.id} value={item.id} className="rounded-none px-3 py-3 text-sm font-medium after:bottom-0">{item.label}</TabsTrigger>)}
        </TabsList>
      </div>
      {flowTabs.map((item) => <TabsContent key={item.id} value={item.id} className="m-0 min-h-0 flex-1 overflow-auto p-4">
        {item.id === "direction" ? <DirectionPanel {...props} services={lookups.telephonyServices} />
          : item.id === "defaults" ? <DefaultsPanel {...props} catalog={catalog} credentialNames={lookups.credentialNames} />
          : item.id === "variables" ? <VariablesPanel {...props} />
          : item.id === "media" ? <MediaPolicyFields {...props} participantKey={null} />
          : item.id === "wait" ? <WaitSoundsPanel {...props} /> : <AdvancedPanel {...props} />}
      </TabsContent>)}
    </Tabs>
  </aside>;
}
