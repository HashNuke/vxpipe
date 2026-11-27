import { createContext, type ReactNode } from "react";

import type { InspectorProps } from "./inspectorTypes";

// Storybook supplies the proposed controls while the call-spec schema is under review.
export const GuardrailInspectorContext = createContext<{
  decisionsField: (scope: "call" | "agent", readOnly: boolean) => ReactNode;
  guardrails: (agent: string, turnSupport: "supported" | "speech_to_speech" | "missing_capability") => ReactNode;
  transferEditor: (props: InspectorProps & { participantKey: string; onClose: () => void }) => ReactNode;
} | null>(null);
