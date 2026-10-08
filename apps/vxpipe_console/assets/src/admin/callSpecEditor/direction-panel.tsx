import { useState } from "react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "../components/ui/dialog";
import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import { switchDirection } from "./edits";
import type { InspectorProps, NamedService } from "./inspectorTypes";

export function DirectionPanel({ document, onChange, issues, services }: InspectorProps & { services: NamedService[] }) {
  const [switching, setSwitching] = useState(false);
  const [phoneService, setPhoneService] = useState("");
  const [agentKey, setAgentKey] = useState("");
  const { source, readOnly } = document;
  const outgoing = Boolean(source.outgoing_call);
  const direction = outgoing ? "outgoing_call" : "incoming_call";
  const block = source.outgoing_call ?? source.incoming_call;
  const handler = block?.handled_by ?? source.entry_receiver ?? "";
  const entry = source.outgoing_call?.callee ?? source.incoming_call?.caller ?? source.entry_caller ?? "";
  const agents = Object.entries(source.participants).filter(([, participant]) => participant.type === "agent").map(([key]) => ({ value: key, label: key }));
  const humans = Object.entries(source.participants).filter(([, participant]) => participant.type === "human").map(([key]) => ({ value: key, label: key }));
  function changeReference(field: "handler" | "entry", value: string) {
    onChange(editSource(document, (next) => {
      if (next.outgoing_call) {
        if (field === "handler") next.outgoing_call.handled_by = value; else next.outgoing_call.callee = value;
      } else if (next.incoming_call) {
        if (field === "handler") next.incoming_call.handled_by = value; else next.incoming_call.caller = value;
      }
    }));
  }
  return <fieldset disabled={readOnly} className="space-y-5">
    <TextField label="Call spec name" path={["name"]} issues={issues} value={source.name ?? ""} onChange={(name) => onChange(editSource(document, (next) => { next.name = name; }))} disabled={readOnly} />
    <div className="flex items-center justify-between gap-3 rounded-md border p-3"><div><p className="text-sm font-medium">{outgoing ? "Outgoing call" : "Incoming call"}</p><p className="text-xs text-muted-foreground">{outgoing ? "Dial a person using a phone service." : "Accept a caller over web or phone."}</p></div>
      <Button variant="outline" size="sm" disabled={readOnly} onClick={() => {
        if (outgoing) onChange(switchDirection(document, "incoming"));
        else { setPhoneService(""); setAgentKey(agents.some((agent) => agent.value === handler) ? handler : ""); setSwitching(true); }
      }}>Switch to {outgoing ? "incoming" : "outgoing"}</Button>
    </div>
    <ChoiceField label={outgoing ? "Callee" : "Caller"} path={[direction, outgoing ? "callee" : "caller"]} issues={issues} value={entry} choices={humans} onChange={(key) => changeReference("entry", key)} disabled={readOnly} />
    <ChoiceField label="Handled by" path={[direction, "handled_by"]} issues={issues} value={handler} choices={outgoing ? agents : [...agents, ...humans].filter(({ value }) => value !== entry)} onChange={(key) => changeReference("handler", key)} disabled={readOnly} hint={outgoing ? "Outgoing calls must be handled by an agent." : "Choose the agent or human who handles the caller."} />
    <p className="text-xs text-muted-foreground">Select the Entry node to configure its connection, opening audio and outgoing ring timeout.</p>
    <Dialog open={switching} onOpenChange={setSwitching}><DialogContent><DialogHeader><DialogTitle>Switch to outgoing</DialogTitle><DialogDescription>The entry participant will use a dial connection. Choose its phone service and the agent that handles the call.</DialogDescription></DialogHeader>
      <ChoiceField label="Outgoing phone service" path={["outgoing_service"]} value={phoneService} choices={[{ value: "", label: "Choose a phone service" }, ...services.map((service) => ({ value: service.key, label: service.name }))]} onChange={setPhoneService} />
      <ChoiceField label="Outgoing handler" path={["outgoing_handler"]} value={agentKey} choices={[{ value: "", label: "Choose an agent" }, ...agents]} onChange={setAgentKey} />
      {!services.length && <p className="text-sm text-muted-foreground">Configure a phone service in Services before choosing outgoing calls.</p>}
      {!agents.length && <p className="text-sm text-muted-foreground">Add an agent to handle outgoing calls.</p>}
      <DialogFooter><Button variant="outline" onClick={() => setSwitching(false)}>Cancel</Button><Button disabled={!phoneService || !agentKey || readOnly} onClick={() => {
        const ready = editSource(document, (next) => { if (next.incoming_call) next.incoming_call.handled_by = agentKey; });
        onChange(switchDirection(ready, "outgoing", phoneService)); setSwitching(false);
      }}>Use outgoing direction</Button></DialogFooter>
    </DialogContent></Dialog>
  </fieldset>;
}
