import { useState, type ReactNode } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";

export type HumanInspectorTab = "connection" | "voice" | "presence";
export function HumanInspectorTabs({ connection, voice, presence, tab, onTabChange }: { connection: ReactNode; voice: ReactNode; presence: ReactNode; tab?: HumanInspectorTab; onTabChange?: (tab: HumanInspectorTab) => void }) {
  const [active, setActive] = useState<HumanInspectorTab>("connection");
  return <Tabs value={tab ?? active} onValueChange={(value) => { setActive(value as HumanInspectorTab); onTabChange?.(value as HumanInspectorTab); }} className="min-h-0 flex-1 gap-0">
    <div className="shrink-0 overflow-x-auto border-b px-4"><TabsList variant="line" aria-label="Participant settings tabs" className="h-auto justify-start gap-1 rounded-none bg-transparent p-0">
      {(["connection", "voice", "presence"] as const).map((key) => <TabsTrigger key={key} value={key} className="rounded-none px-3 py-3 text-sm after:bottom-0">{key === "connection" ? "Connection" : key === "voice" ? "Voice and model" : "Presence"}</TabsTrigger>)}
    </TabsList></div>
    <TabsContent value="connection" className="m-0 min-h-0 flex-1 overflow-auto p-4">{connection}</TabsContent>
    <TabsContent value="voice" className="m-0 min-h-0 flex-1 overflow-auto p-4">{voice}</TabsContent>
    <TabsContent value="presence" className="m-0 min-h-0 flex-1 overflow-auto p-4">{presence}</TabsContent>
  </Tabs>;
}
