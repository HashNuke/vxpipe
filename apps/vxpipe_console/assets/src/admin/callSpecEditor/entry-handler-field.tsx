import { ChoiceField } from "./editor-fields";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";

export function EntryHandlerField({ document, onChange, issues }: InspectorProps) {
  const { source, readOnly } = document;
  const outgoing = Boolean(source.outgoing_call);
  const direction = outgoing ? "outgoing_call" : "incoming_call";
  const block = source.outgoing_call ?? source.incoming_call;
  const handler = block?.handled_by ?? source.entry_receiver ?? "";
  const entry = source.outgoing_call?.callee ?? source.incoming_call?.caller ?? source.entry_caller ?? "";
  const agents = Object.entries(source.participants).filter(([, participant]) => participant.type === "agent").map(([key]) => ({ value: key, label: key }));
  const humans = Object.entries(source.participants).filter(([, participant]) => participant.type === "human").map(([key]) => ({ value: key, label: key }));
  function changeHandler(value: string) {
    onChange(editSource(document, (next) => {
      if (next.outgoing_call) next.outgoing_call.handled_by = value;
      else if (next.incoming_call) next.incoming_call.handled_by = value;
    }));
  }
  return <ChoiceField label="Handled by" path={[direction, "handled_by"]} issues={issues} value={handler} choices={outgoing ? agents : [...agents, ...humans].filter(({ value }) => value !== entry)} onChange={changeHandler} disabled={readOnly} hint={outgoing ? "Outgoing calls must be handled by an agent." : "Choose the agent or human who handles the caller."} />;
}
