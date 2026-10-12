import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import { participant } from "./edits";
import { useState } from "react";
import { PhoneConnectionDialog } from "./phone-connection-dialog";
import { useIssueField } from "./issue-context";
import type { InspectorProps, NamedService, PhoneNumberLoader } from "./inspectorTypes";
import type { Connection } from "./types";

export function ConnectionFields({ document, onChange, issues, participantKey, services, loadNumbers }: InspectorProps & { participantKey: string; services: NamedService[]; loadNumbers?: PhoneNumberLoader }) {
  const [phoneOpen, setPhoneOpen] = useState(false);
  const path = ["participants", participantKey, "connection"];
  const { ref, errors } = useIssueField(path, issues, false);
  const target = participant(document.source, participantKey);
  if (target.type !== "human") return null;
  const connection = target.connection;
  const outgoing = document.source.outgoing_call?.callee === participantKey;
  const incoming = (document.source.incoming_call?.caller ?? document.source.entry_caller) === participantKey;
  const web = connection.service === "web";
  const selectedService = services.find((item) => item.key === connection.service);
  const serviceName = selectedService?.provider === "twilio" ? "Twilio" : selectedService?.provider === "telnyx" ? "Telnyx" : selectedService?.name ?? connection.service;
  const numberSource = connection.number_from_variable ? "variable" : Object.hasOwn(connection, "number") || !outgoing ? "fixed" : "request";
  const sections = document.source.call_variables?.sections ?? {};
  const reference = connection.number_from_variable;
  const section = reference && Object.hasOwn(sections, reference.section) ? sections[reference.section] : undefined;
  const variables = Object.entries(section?.schema.properties ?? {}).filter(([, schema]) => schema.type === "string" || (Array.isArray(schema.type) && schema.type.includes("string")));
  function change(edit: (next: Connection) => void) {
    onChange(editSource(document, (source) => {
      const target = participant(source, participantKey);
      if (target.type === "human") edit(target.connection);
    }));
  }
  return <div ref={ref} tabIndex={-1} data-field-path={JSON.stringify(path)} className="outline-none focus-visible:ring-2 focus-visible:ring-ring"><fieldset disabled={document.readOnly} className="space-y-4">
    <fieldset className="space-y-2"><legend className="mb-2 text-sm font-medium">Connection</legend><div className="grid grid-cols-2 gap-2">
      <label className={`flex items-center gap-2 rounded-md border p-2.5 text-sm ${web ? "border-primary bg-primary/10" : "border-border"} ${outgoing ? "opacity-50" : "cursor-pointer"}`}><input type="radio" name={`connection-${participantKey}`} aria-label="Web" checked={web} disabled={document.readOnly || outgoing} onChange={() => change((next) => { next.service = "web"; next.mode = "receive"; next.admission = incoming ? "start_call" : "transfer"; delete next.number; delete next.number_from_variable; })} className="accent-primary" /><span className="min-w-0"><span className="block font-medium">Web</span><span className="block text-xs text-muted-foreground">WebRTC</span></span></label>
      <label className={`flex cursor-pointer items-center gap-2 rounded-md border p-2.5 text-sm ${!web ? "border-primary bg-primary/10" : "border-border"}`}><input type="radio" name={`connection-${participantKey}`} aria-label="Phone" checked={!web} disabled={document.readOnly} onChange={() => {}} onClick={() => setPhoneOpen(true)} className="accent-primary" /><span className="min-w-0"><span className="block font-medium">Phone</span><span className="block truncate text-xs text-muted-foreground">{web ? "—" : `${serviceName} · ${connection.number || "—"}`}</span></span></label>
    </div></fieldset>
    {phoneOpen && !document.readOnly && <PhoneConnectionDialog services={services} currentService={connection.service} currentNumber={connection.number} incoming={incoming} loadNumbers={loadNumbers} onCancel={() => setPhoneOpen(false)} onSelect={(service, number) => {
      change((next) => { next.service = service; next.mode = incoming ? "receive" : "dial"; next.admission = incoming || outgoing ? "start_call" : "transfer"; if (incoming) { next.number = number; delete next.number_from_variable; } else if (!outgoing && next.number === undefined && !next.number_from_variable) next.number = ""; });
      setPhoneOpen(false);
    }} />}
    <p className="text-xs text-muted-foreground">{incoming ? "This connection accepts the caller and starts the call." : outgoing ? "The selected phone service dials the callee." : web ? "This person joins over the web when a transfer invites them." : "The selected phone service dials this person for a transfer."}</p>
    {!web && <>
      {!incoming && <ChoiceField label="Number source" path={path} value={numberSource} issues={issues} disabled={document.readOnly}
        choices={[{ value: "fixed", label: "Fixed number" }, outgoing ? { value: "request", label: "Outgoing request (to)" } : { value: "variable", label: "Call variable" }]}
        onChange={(mode) => change((next) => {
          delete next.number; delete next.number_from_variable;
          if (mode === "fixed") next.number = "";
          else if (mode === "variable") next.number_from_variable = { section: "", variable: "" };
        })} />}
      {numberSource === "fixed" && !incoming && <TextField label="Phone number" path={[...path, "number"]} value={connection.number ?? ""} issues={issues} disabled={document.readOnly} hint="Use the full international number, for example +15550001000."
        onChange={(number) => change((next) => { next.number = number; })} />}
      {numberSource === "request" && <p className="text-xs text-muted-foreground">Each outgoing call request must supply its destination in to.</p>}
      {numberSource === "variable" && <>
        <ChoiceField label="Variable section" path={[...path, "number_from_variable", "section"]} value={reference?.section ?? ""} issues={issues} disabled={document.readOnly}
          choices={[{ value: "", label: "Choose a section" }, ...Object.keys(sections).map((key) => ({ value: key, label: key }))]}
          onChange={(section) => change((next) => { next.number_from_variable = { section, variable: "" }; })} />
        <ChoiceField label="Phone variable" path={[...path, "number_from_variable", "variable"]} value={reference?.variable ?? ""} issues={issues} disabled={document.readOnly}
          choices={[{ value: "", label: "Choose a string variable" }, ...variables.map(([key]) => ({ value: key, label: key }))]}
          onChange={(variable) => change((next) => { next.number_from_variable = { section: reference?.section ?? "", variable }; })}
          hint="The variable must contain an international phone number. Agents cannot have write access to its section." />
      </>}
    </>}
    {errors.map((issue, index) => <p key={index} className="text-xs text-destructive">{issue.reason}</p>)}
  </fieldset></div>;
}
