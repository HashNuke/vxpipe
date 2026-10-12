import { ParticipantSource } from "./participant-source";
import { PhoneIncoming, PhoneOutgoing } from "lucide-react";
import type { ModelCatalog } from "../modelCatalog";
import { EntryHandlerField } from "./entry-handler-field";
import { ConnectionFields } from "./connection-fields";
import { NumberField } from "./editor-fields";
import { editSource } from "./editSource";
import { HumanInspectorTabs, type HumanInspectorTab } from "./human-inspector-tabs";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { MediaPolicyFields } from "./media-policy-fields";
import { OpeningAudioFields } from "./opening-audio-fields";
import { ParticipantCapabilities } from "./participant-capabilities";
import { renameParticipant } from "./participants";
import { RenameField } from "./rename-field";

export function InboundInspector({ catalog, lookups, tab, onTabChange, ...props }: InspectorProps & { catalog: ModelCatalog; lookups: EditorLookups; tab?: HumanInspectorTab; onTabChange?: (tab: HumanInspectorTab) => void }) {
  const { document, onChange, issues } = props;
  const { source, readOnly } = document;
  const key = source.incoming_call?.caller ?? source.outgoing_call?.callee ?? source.entry_caller;
  if (!key || !Object.hasOwn(source.participants, key)) return <p className="p-4 text-sm">The Entry participant is missing. Restore it in the call spec JSON.</p>;
  const Icon = source.outgoing_call ? PhoneOutgoing : PhoneIncoming;
  return <aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-background">
    <ParticipantSource {...props} participantKey={key} heading={<><Icon className="h-4 w-4" /><span>Entry · {source.outgoing_call ? "Callee" : "Caller"}</span></>}>
    <HumanInspectorTabs document={document} issues={issues} focusRequest={props.focusRequest} nodeId={"$entry"} tab={tab} onTabChange={onTabChange} connection={<div className="space-y-5 text-sm">
      <RenameField key={key} name={key} label="Participant key" path={["participants", key]} disabled={readOnly} onRename={(next) => onChange(renameParticipant(document, key, next))} />
      <EntryHandlerField {...props} />
      <ConnectionFields {...props} participantKey={key} services={lookups.telephonyServices} loadNumbers={lookups.phoneNumbers} />
      {source.outgoing_call && <NumberField label="Ring timeout (ms)" path={["outgoing_call", "ring_timeout_ms"]} issues={issues} disabled={readOnly} value={source.outgoing_call.ring_timeout_ms} hint="5,000–60,000 ms. Leave blank for the 30,000 ms default."
        onChange={(value) => onChange(editSource(document, (source) => { if (source.outgoing_call) { if (value === undefined) delete source.outgoing_call.ring_timeout_ms; else source.outgoing_call.ring_timeout_ms = value; } }))} />}
      <OpeningAudioFields {...props} catalog={catalog} />
    </div>} voice={<ParticipantCapabilities {...props} participantKey={key} catalog={catalog} />} presence={<MediaPolicyFields {...props} participantKey={key} />} />
    </ParticipantSource>
  </aside>;
}
