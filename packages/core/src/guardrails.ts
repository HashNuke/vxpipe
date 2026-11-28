/** Private, permission-filtered evidence from one participant's Guardrails service. */
export interface GuardrailEvaluation {
  id: string;
  participantId: string;
  occurredAt: string;
  event: "before_turn" | "after_turn" | "before_outgoing_transfer";
  outcome: "passed" | "blocked" | "error" | "cancelled" | "skipped_empty" | "not_applicable" | "pending";
  activationId?: string;
  sourceParticipantId?: string;
  sourceTurnId?: string;
  responseTurnId?: string;
  commandId?: string;
  candidateAttemptId?: string;
  transferInvocationId?: string;
  deliveredFactId?: string;
  destinationParticipantId?: string;
  transferOutcome?: "completed" | "failed";
  messageId?: string;
  selectedProvider?: string;
  selectedModel?: string;
  actualProvider?: string;
  actualModel?: string;
  actualRequestId?: string;
  policyRevision?: number;
  policyDigest?: string;
  startedAt?: string;
  endedAt?: string;
  durationMs?: number;
  errorCode?: string;
  contentUnavailable?: "denied" | "unknown";
  checkedText?: string;
  proposedTools?: readonly { id: string; name: string }[];
  questionIds?: readonly string[];
  attemptIds?: readonly string[];
  questions: readonly GuardrailQuestionResult[];
  attempts: readonly GuardrailAttempt[];
}

export interface GuardrailQuestionResult {
  id: string;
  ordinal: number;
  requiredAnswer: "yes" | "no";
  thresholdHundredths: number;
  outcome: "passed" | "failed" | "unavailable";
  question?: string;
  probabilityYes?: number;
  inferredAnswer?: "yes" | "no";
  feedback?: string;
  feedbackOrigin?: "configured" | "authored" | "fallback";
  feedbackDispatched?: boolean;
}

export interface GuardrailAttempt {
  id: string;
  ordinal: number;
  outcome: "succeeded" | "failed" | "cancelled" | "pending";
  errorCode?: string;
  provider?: string;
  model?: string;
  requestId?: string;
  retryOf?: string;
  startedAt?: string;
  endedAt?: string;
  durationMs?: number;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  /** Settled decimal amounts are strings to preserve ledger precision. */
  costs?: readonly { currency: string; amount: string }[];
}
