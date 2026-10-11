import type { ModelCatalog } from "../modelCatalog";
import { agentModelKinds, agentModelMode, canSelectAgentModels, setAgentModelMode } from "./agent-models";
import { ChoiceField } from "./editor-fields";
import type { InspectorProps } from "./inspectorTypes";
import { ParticipantCapabilities } from "./participant-capabilities";

export function AgentModelsPanel(props: InspectorProps & { participantKey: string; catalog: ModelCatalog }) {
  const { document, participantKey, catalog, onChange, issues } = props;
  const mode = agentModelMode(document.source, participantKey);
  return <div className="space-y-5">
    <ChoiceField label="Model type" layout="inline" path={["participants", participantKey, "capabilities"]} issues={issues} disabled={document.readOnly} value={mode}
      choices={[
        { value: "speech_to_speech", label: "Speech-to-Speech", disabled: !canSelectAgentModels(document.source, participantKey, "speech_to_speech", catalog) },
        { value: "llm", label: "LLM + Text-to-Speech", disabled: !canSelectAgentModels(document.source, participantKey, "llm", catalog) },
      ]}
      hint={mode === "speech_to_speech" ? "One model handles speech input and speech output." : "Choose an LLM for responses and Text-to-Speech for this agent's voice."}
      onChange={(next) => { if (next === "llm" || next === "speech_to_speech") onChange(setAgentModelMode(document, participantKey, next, catalog)); }} />
    <ParticipantCapabilities {...props} kinds={agentModelKinds[mode]} required />
  </div>;
}
