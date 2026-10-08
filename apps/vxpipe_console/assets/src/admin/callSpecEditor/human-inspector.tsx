import { useState } from "react";
import { Handshake, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "../components/ui/dialog";
import type { ModelCatalog } from "../modelCatalog";
import { ConnectionFields } from "./connection-fields";
import { NumberField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import { participant } from "./edits";
import { HumanInspectorTabs, type HumanInspectorTab } from "./human-inspector-tabs";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { MediaPolicyFields } from "./media-policy-fields";
import { ParticipantCapabilities } from "./participant-capabilities";
import { removeParticipant, renameParticipant } from "./participants";
import { RenameField } from "./rename-field";

export function HumanInspector({ catalog, lookups, participantKey, onRenamed, onRemoved, tab, onTabChange, ...props }: InspectorProps & { catalog: ModelCatalog; lookups: EditorLookups; participantKey: string; onRenamed?: (key: string) => void; onRemoved?: () => void; tab?: HumanInspectorTab; onTabChange?: (tab: HumanInspectorTab) => void }) {
  const [deleting, setDeleting] = useState(false);
  const { document, onChange, issues } = props;
  const target = participant(document.source, participantKey);
  if (target.type !== "human") return null;
  const path = ["participants", participantKey];
  const entry = document.source.incoming_call?.caller ?? document.source.outgoing_call?.callee ?? document.source.entry_caller;
  return <aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-background">
    <div className="shrink-0 p-4 pb-2"><div className="flex items-center justify-between gap-3 text-xs font-medium uppercase tracking-wide text-muted-foreground">
      <div className="flex items-center gap-2"><Handshake className="h-3.5 w-3.5" /><span>Human destination</span></div>
      {participantKey !== entry && <Button variant="ghost" size="icon-sm" aria-label="Delete participant" disabled={document.readOnly} onClick={() => setDeleting(true)}><Trash2 className="h-4 w-4" /></Button>}
    </div></div>
    <HumanInspectorTabs tab={tab} onTabChange={onTabChange} connection={<div className="space-y-5">
      <RenameField key={participantKey} name={participantKey} label="Participant key" path={path} disabled={document.readOnly} onRename={(key) => { onChange(renameParticipant(document, participantKey, key)); onRenamed?.(key); }} />
      <TextField label="Description" path={[...path, "description"]} issues={issues} disabled={document.readOnly} multiline value={target.description ?? ""}
        onChange={(description) => onChange(editSource(document, (source) => { const target = participant(source, participantKey); if (description === "") delete target.description; else target.description = description; }))} />
      <ConnectionFields {...props} participantKey={participantKey} services={lookups.telephonyServices} />
      <TextField label="Private briefing" path={[...path, "transfer_notice"]} issues={issues} disabled={document.readOnly} multiline value={target.transfer_notice ?? ""} hint="Spoken privately to this person before they join the caller."
        onChange={(notice) => onChange(editSource(document, (source) => { const human = participant(source, participantKey); if (human.type === "human") { if (notice === "") delete human.transfer_notice; else human.transfer_notice = notice; } }))} />
      <section className="space-y-3 rounded-md border border-border bg-muted/30 p-3" aria-label="Transfer timing">
        <NumberField label="Transfer attempt timeout (ms)" path={["transfer_policy", "attempt_timeout_ms"]} issues={issues} disabled={document.readOnly} value={document.source.transfer_policy?.attempt_timeout_ms} hint="Applies to all transfers in this call. 1,000–120,000 ms; leave blank for the runtime default."
          onChange={(value) => onChange(editSource(document, (source) => { source.transfer_policy ??= {}; if (value === undefined) delete source.transfer_policy.attempt_timeout_ms; else source.transfer_policy.attempt_timeout_ms = value; }))} />
      </section>
    </div>} voice={<ParticipantCapabilities {...props} participantKey={participantKey} catalog={catalog} credentialNames={lookups.credentialNames} />} presence={<MediaPolicyFields {...props} participantKey={participantKey} />} />
    <Dialog open={deleting} onOpenChange={setDeleting}><DialogContent><DialogHeader><DialogTitle>Delete {participantKey}?</DialogTitle><DialogDescription>Remove this participant and its references from transfers, routes and overrides. If it handles incoming calls, choose a new handler before saving.</DialogDescription></DialogHeader><DialogFooter>
      <Button variant="outline" onClick={() => setDeleting(false)}>Cancel</Button><Button variant="destructive" disabled={document.readOnly} onClick={() => { onChange(removeParticipant(document, participantKey)); setDeleting(false); onRemoved?.(); }}>Delete participant</Button>
    </DialogFooter></DialogContent></Dialog>
  </aside>;
}
