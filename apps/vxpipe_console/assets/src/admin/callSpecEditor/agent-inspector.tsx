import { useLayoutEffect, useRef, useState } from "react";
import { Bot, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import type { ModelCatalog } from "../modelCatalog";
import { AgentPromptPanel } from "./agent-prompt-panel";
import { AgentToolsPanel } from "./agent-tools-panel";
import { AgentTransfersPanel } from "./agent-transfers-panel";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { MediaPolicyFields } from "./media-policy-fields";
import { ParticipantCapabilities } from "./participant-capabilities";
import { removeParticipant, renameParticipant } from "./participants";
import { RenameField } from "./rename-field";
import { SectionPermissionMatrix } from "./section-permission-matrix";

const tabs = [
  { id: "prompt", label: "Prompt" }, { id: "voice", label: "Voice and model" },
  { id: "variables", label: "Variables" }, { id: "transfers", label: "Transfers" },
  { id: "tools", label: "Tools" }, { id: "presence", label: "Presence" },
] as const;
export type AgentInspectorTab = typeof tabs[number]["id"];
export function AgentInspector({ catalog, lookups, participantKey, onRenamed, onRemoved, tab, onTabChange, ...props }: InspectorProps & { catalog: ModelCatalog; lookups: EditorLookups; participantKey: string; onRenamed?: (key: string) => void; onRemoved?: () => void; tab?: AgentInspectorTab; onTabChange?: (tab: AgentInspectorTab) => void }) {
  const [active, setActive] = useState<AgentInspectorTab>("prompt");
  const [deleting, setDeleting] = useState(false);
  const tabBar = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => { tabBar.current?.querySelector<HTMLElement>('[role="tab"][data-state="active"]')?.scrollIntoView({ block: "nearest", inline: "nearest" }); }, [tab, active]);
  const { document, onChange } = props;
  return <aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-background">
    <div className="shrink-0 space-y-3 p-4 pb-2"><div className="flex items-center justify-between gap-3 text-xs font-medium uppercase tracking-wide text-muted-foreground">
      <div className="flex items-center gap-2"><Bot className="h-3.5 w-3.5" /><span>Agent</span></div><Button variant="ghost" size="icon-sm" aria-label="Delete participant" disabled={document.readOnly} onClick={() => setDeleting(true)}><Trash2 className="h-4 w-4" /></Button>
    </div><RenameField key={participantKey} name={participantKey} label="Participant key" path={["participants", participantKey]} disabled={document.readOnly} onRename={(key) => { onChange(renameParticipant(document, participantKey, key)); onRenamed?.(key); }} /></div>
    <Tabs value={tab ?? active} onValueChange={(value) => { setActive(value as AgentInspectorTab); onTabChange?.(value as AgentInspectorTab); }} className="min-h-0 flex-1 gap-0">
      <div ref={tabBar} className="shrink-0 overflow-x-auto border-b px-4"><TabsList variant="line" aria-label="Agent settings" className="h-auto justify-start gap-1 rounded-none bg-transparent p-0">
        {tabs.map(({ id, label }) => <TabsTrigger key={id} value={id} className="rounded-none px-3 py-3 text-sm after:bottom-0">{label}</TabsTrigger>)}
      </TabsList></div>
      {tabs.map(({ id }) => <TabsContent key={id} value={id} className="m-0 min-h-0 flex-1 overflow-auto p-4">
        {id === "prompt" ? <AgentPromptPanel {...props} participantKey={participantKey} />
          : id === "voice" ? <ParticipantCapabilities {...props} participantKey={participantKey} catalog={catalog} credentialNames={lookups.credentialNames} />
          : id === "variables" ? <SectionPermissionMatrix {...props} agentKey={participantKey} />
          : id === "transfers" ? <AgentTransfersPanel {...props} participantKey={participantKey} />
          : id === "tools" ? <AgentToolsPanel {...props} participantKey={participantKey} integrations={lookups.mcpIntegrations} />
          : <MediaPolicyFields {...props} participantKey={participantKey} />}
      </TabsContent>)}
    </Tabs>
    <Dialog open={deleting} onOpenChange={setDeleting}><DialogContent><DialogHeader><DialogTitle>Delete {participantKey}?</DialogTitle><DialogDescription>Remove this agent and its references from transfers, routes and overrides. If it handles the call, choose a new handler before saving.</DialogDescription></DialogHeader><DialogFooter>
      <Button variant="outline" onClick={() => setDeleting(false)}>Cancel</Button><Button variant="destructive" disabled={document.readOnly} onClick={() => { onChange(removeParticipant(document, participantKey)); setDeleting(false); onRemoved?.(); }}>Delete participant</Button>
    </DialogFooter></DialogContent></Dialog>
  </aside>;
}
