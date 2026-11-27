import { useState, type ReactNode } from "react";
import { QuestionSection, type Question } from "./guardrail-story-questions";
import { ChoiceField } from "./editor-fields";
import { TransferToolStoryEditor } from "./transfer-tool-story-editor";
import { GuardrailInspectorContext } from "./guardrail-inspector-context";

const input: Question[] = [{ id: "private_request", text: "Is the caller asking for another patient’s appointment details?", threshold: "" }];
const output: Question[] = [{ id: "private_details", text: "Does the reply reveal another patient’s appointment details?", threshold: "" }];
const transfer: Question[] = [{ id: "transfer_consent", text: "Is the caller’s consent to this transfer missing?", threshold: "" }];

type AgentQuestions = { input: Question[]; output: Question[]; transfer: Question[] };
const emptyAgentQuestions: AgentQuestions = { input: [], output: [], transfer: [] };

export function GuardrailStoryPanels({ children }: { children: ReactNode }) {
  const [decisionsModel, setDecisionsModel] = useState("jev-1.14.0");
  const [agents, setAgents] = useState<Record<string, AgentQuestions>>({
    intake: { input, output, transfer },
    scheduling: { ...emptyAgentQuestions, transfer: [{ id: "appointment_reference", text: "Is the appointment reference missing?", threshold: "" }] },
  });
  function edit(agent: string, patch: Partial<AgentQuestions>) {
    setAgents(current => ({ ...current, [agent]: { ...(current[agent] ?? emptyAgentQuestions), ...patch } }));
  }
  return <GuardrailInspectorContext.Provider value={{
    decisionsField(scope, readOnly) {
      return <ChoiceField label="Decisions" path={["defaults", "capabilities", "guardrail"]}
        value={decisionsModel} onChange={setDecisionsModel} disabled={readOnly || scope === "agent"}
        choices={[{ value: "jev-1.14.0", label: "Jev · jev-1.14.0" }, { value: "gpt-6-luna", label: "OpenAI Decisions · gpt-6-luna" }]}
        hint={scope === "agent" ? "Change the Decisions model in Call settings → Models." : "Used for guardrail checks across all AI agents in this call."} />;
    },
    guardrails(agent, turnSupport) {
      const unavailable = turnSupport === "speech_to_speech" ? "Speech-to-speech does not expose a reliable turn boundary."
        : turnSupport === "missing_capability" ? "Select an LLM and a text-to-speech model to use this check." : undefined;
      const questions = agents[agent] ?? emptyAgentQuestions;
      return <div key={agent} className="space-y-7">
        <QuestionSection title="Before turn" unavailable={unavailable} timing="Before the transcript reaches the LLM."
          questions={questions.input} change={input => edit(agent, { input })} />
        <QuestionSection title="After turn" unavailable={unavailable} timing="Before tool calls or text-to-speech."
          questions={questions.output} change={output => edit(agent, { output })} />
        <QuestionSection title="Before outgoing transfer" timing={`Before ${agent} transfers to any destination.`}
          questions={questions.transfer} change={transfer => edit(agent, { transfer })} />
      </div>;
    },
    transferEditor: props => <TransferToolStoryEditor {...props} />,
  }}>{children}</GuardrailInspectorContext.Provider>;
}
