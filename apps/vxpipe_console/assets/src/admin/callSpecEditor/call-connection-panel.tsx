import { EntryHandlerField } from "./entry-handler-field";
import { ConnectionFields } from "./connection-fields";
import { DurationField } from "./editor-fields";
import { editSource } from "./editSource";
import type { EditorLookups, InspectorProps } from "./inspectorTypes";
import { OpeningAudioFields } from "./opening-audio-fields";

export function CallConnectionPanel({ lookups, onOpenModels, ...props }: InspectorProps & {
  lookups: Pick<EditorLookups, "telephonyServices" | "phoneNumbers">;
  onOpenModels: () => void;
}) {
  const { document, onChange, issues } = props;
  const { source, readOnly } = document;
  const key = source.incoming_call?.caller ?? source.outgoing_call?.callee ?? source.entry_caller;
  if (!key || !Object.hasOwn(source.participants, key)) return <p className="text-sm">The Entry participant is missing. Restore it in the call spec JSON.</p>;
  return <div className="space-y-5 text-sm">
    <EntryHandlerField {...props} />
    <ConnectionFields {...props} participantKey={key} services={lookups.telephonyServices} loadNumbers={lookups.phoneNumbers} />
    {source.outgoing_call && <DurationField label="Ring timeout (seconds)" path={["outgoing_call", "ring_timeout_ms"]} issues={issues} disabled={readOnly} value={source.outgoing_call.ring_timeout_ms} hint="5–60 seconds. Leave blank for the 30-second default."
      onChange={(value) => onChange(editSource(document, (source) => { if (source.outgoing_call) { if (value === undefined) delete source.outgoing_call.ring_timeout_ms; else source.outgoing_call.ring_timeout_ms = value; } }))} />}
    <OpeningAudioFields {...props} onOpenModels={onOpenModels} />
  </div>;
}
