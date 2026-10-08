import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import { agent, setFirstMessage } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

export function AgentPromptPanel({ document, onChange, issues, participantKey }: InspectorProps & { participantKey: string }) {
  const target = agent(document.source, participantKey);
  const path = ["participants", participantKey];
  const generated = document.source.outgoing_call?.handled_by === participantKey;
  return <fieldset disabled={document.readOnly} className="space-y-5">
    <TextField label="Prompt" path={[...path, "prompt"]} issues={issues} disabled={document.readOnly} value={target.prompt} multiline rows={10} hint="Instructions for how this agent should handle the conversation."
      onChange={(prompt) => onChange(editSource(document, (source) => { agent(source, participantKey).prompt = prompt; }))} />
    <TextField label="Description" path={[...path, "description"]} issues={issues} disabled={document.readOnly} value={target.description ?? ""} multiline hint="Describe this agent's role to other participants."
      onChange={(description) => onChange(editSource(document, (source) => { const target = agent(source, participantKey); if (description === "") delete target.description; else target.description = description; }))} />
    <ChoiceField label="First message" path={[...path, "first_message", "mode"]} issues={issues} disabled={document.readOnly} value={target.first_message?.mode ?? ""}
      choices={[{ value: "", label: `Default (${generated ? "generated" : "wait for input"})` }, { value: "wait_for_input", label: "Wait for input" }, { value: "generated", label: "Generated" }, { value: "fixed", label: "Fixed text" }]}
      hint={generated ? "The outgoing handler introduces the call by default." : "This agent waits for input by default."}
      onChange={(mode) => onChange(setFirstMessage(document, participantKey, mode === "fixed" ? { mode, text: "" } : mode === "generated" || mode === "wait_for_input" ? { mode } : undefined))} />
    {target.first_message?.mode === "fixed" && <TextField label="First message text" path={[...path, "first_message", "text"]} issues={issues} disabled={document.readOnly} value={target.first_message.text} multiline
      onChange={(text) => onChange(setFirstMessage(document, participantKey, { mode: "fixed", text }))} />}
  </fieldset>;
}
