import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import { participant } from "./edits";
import type { InspectorProps, NamedService } from "./inspectorTypes";
import type { Connection } from "./types";

export function ConnectionFields({ document, onChange, issues, participantKey, services }: InspectorProps & { participantKey: string; services: NamedService[] }) {
  const target = participant(document.source, participantKey);
  if (target.type !== "human") return null;
  const connection = target.connection;
  const path = ["participants", participantKey, "connection"];
  const outgoing = document.source.outgoing_call?.callee === participantKey;
  const incoming = (document.source.incoming_call?.caller ?? document.source.entry_caller) === participantKey;
  const web = connection.service === "web";
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
  return <fieldset disabled={document.readOnly} className="space-y-4">
    <ChoiceField label="Connection service" path={[...path, "service"]} value={connection.service} issues={issues} disabled={document.readOnly}
      choices={[...(!outgoing ? [{ value: "web", label: "Web" }] : []), ...services.map((service) => ({ value: service.key, label: service.name }))]}
      onChange={(service) => change((next) => {
        next.service = service;
        next.mode = service === "web" || incoming ? "receive" : "dial";
        next.admission = incoming || outgoing ? "start_call" : "transfer";
        if (service === "web") { delete next.number; delete next.number_from_variable; }
        else if (!outgoing && !next.number_from_variable && next.number === undefined) next.number = "";
      })} />
    <p className="text-xs text-muted-foreground">{incoming ? "This connection accepts the caller and starts the call." : outgoing ? "The selected phone service dials the callee." : web ? "This person joins over the web when a transfer invites them." : "The selected phone service dials this person for a transfer."}</p>
    {!web && <>
      {!incoming && <ChoiceField label="Number source" path={path} value={numberSource} issues={issues} disabled={document.readOnly}
        choices={[{ value: "fixed", label: "Fixed number" }, outgoing ? { value: "request", label: "Outgoing request (to)" } : { value: "variable", label: "Call variable" }]}
        onChange={(mode) => change((next) => {
          delete next.number; delete next.number_from_variable;
          if (mode === "fixed") next.number = "";
          else if (mode === "variable") next.number_from_variable = { section: "", variable: "" };
        })} />}
      {numberSource === "fixed" && <TextField label="Phone number" path={[...path, "number"]} value={connection.number ?? ""} issues={issues} disabled={document.readOnly} hint="Use the full international number, for example +15550001000."
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
  </fieldset>;
}
