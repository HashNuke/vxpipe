import { guardrailEventTitles, guardrailEvents, setGuardrailQuestions } from "./guardrails";
import { QuestionSection } from "./guardrail-questions";
import { agentModelMode } from "./agent-models";
import { agent } from "./edits";
import type { GuardrailEvent } from "./types";
import type { InspectorProps } from "./inspectorTypes";

const timing: Record<GuardrailEvent, string> = {
  before_turn: "Before the transcript reaches the LLM.",
  after_turn: "Before tool calls or text-to-speech.",
  before_outgoing_transfer: "Before a transfer leaves this agent.",
};

export function GuardrailsPanel({ document, onChange, participantKey }: InspectorProps & { participantKey: string }) {
  const source = document.source;
  const participant = agent(source, participantKey);
  const defaults = source.defaults?.capabilities;
  const hasLlm = participant.capabilities?.model_inference ?? defaults?.model_inference;
  const hasTts = participant.capabilities?.text_to_speech ?? defaults?.text_to_speech;
  const turnSupport = agentModelMode(source, participantKey) === "speech_to_speech"
    ? "speech_to_speech" as const : hasLlm && hasTts ? "supported" as const : "missing_capability" as const;
  const turnUnavailable = turnSupport === "speech_to_speech"
    ? "Speech-to-speech does not expose a reliable turn boundary."
    : turnSupport === "missing_capability" ? "Select an LLM and a text-to-speech model to use this check." : undefined;
  const guardrails = participant.guardrails ?? {};
  return <div className="space-y-7">
    {guardrailEvents.map((event) => {
      const unavailable = event === "before_outgoing_transfer" ? undefined : turnUnavailable;
      const questions = guardrails[event] ?? [];
      return <QuestionSection key={`${participantKey}:${event}`} title={guardrailEventTitles[event]}
        timing={event === "before_outgoing_transfer" ? `Before ${participantKey} transfers to any destination.` : timing[event]}
        unavailable={unavailable} questions={questions} disabled={document.readOnly}
        onChange={(next) => onChange(setGuardrailQuestions(document, participantKey, event, next))} />;
    })}
  </div>;
}
