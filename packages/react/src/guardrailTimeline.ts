import type { GuardrailEvaluation, Message, ToolCall } from "@vxpipe/core";
import type { HistoryFilters } from "./historyFilters.js";

export interface GuardrailRow {
  id: string;
  participantId: string;
  occurredAt: string;
  checks: GuardrailEvaluation[];
  text?: string;
  label: string;
  tools: { id: string; name: string; requestedDestination?: string }[];
  blocked: boolean;
}

function failed(check: GuardrailEvaluation) {
  return ["blocked", "error", "cancelled"].includes(check.outcome);
}

function candidateKey(check: GuardrailEvaluation): string {
  return check.event !== "before_turn" && check.candidateAttemptId
    ? JSON.stringify([check.participantId, check.activationId, check.commandId, check.candidateAttemptId])
    : JSON.stringify([check.id]);
}

function ownerMessage(check: GuardrailEvaluation, messages: readonly Message[]) {
  const input = check.event === "before_turn";
  const participant = input ? check.sourceParticipantId : check.participantId;
  const turn = input ? check.sourceTurnId : check.responseTurnId;
  if (check.messageId) {
    return messages.find(message =>
      message.id === check.messageId && (!participant || message.participantId === participant) &&
      (!turn || message.turnId === turn));
  }

}

function attach(map: Map<string, GuardrailEvaluation[]>, id: string, checks: GuardrailEvaluation[]) {
  map.set(id, [...(map.get(id) ?? []), ...checks]);
}

export function guardrailTimeline(
  checks: readonly GuardrailEvaluation[],
  messages: readonly Message[],
  tools: readonly ToolCall[],
  filters: HistoryFilters,
) {
  const messageChecks = new Map<string, GuardrailEvaluation[]>();
  const toolChecks = new Map<string, GuardrailEvaluation[]>();
  const privateRows: GuardrailRow[] = [];
  const withheldTools = new Set<string>();
  const groups = new Map<string, GuardrailEvaluation[]>();
  for (const check of checks) attach(groups, candidateKey(check), [check]);

  for (const [id, group] of groups) {
    const first = group[0]!;
    const input = first.event === "before_turn";
    const after = group.find(check => check.event === "after_turn");
    const transfer = group.find(check => check.event === "before_outgoing_transfer");
    const stopped = group.some(failed);
    const blocked = group.some(check => check.outcome === "blocked");
    const proposed = new Map<string, { id: string; name: string }>();
    for (const check of group) {
      if (check.contentUnavailable) continue;
      for (const tool of check.proposedTools ?? []) proposed.set(tool.id, tool);
    }
    const invocation = transfer?.transferInvocationId;
    const transferTool = invocation && tools.find(tool => tool.id === invocation);
    if (invocation && !transfer.contentUnavailable && !proposed.has(invocation)) {
      proposed.set(invocation, { id: invocation, name: "transfer" });
    }
    // Native tools may announce a call before the guardrail denies execution. No such call proves delivery.
    if (stopped && transferTool && transferTool.status !== "completed") withheldTools.add(transferTool.id);

    const visible = group.filter(check =>
      filters.guardrails === "All" || (filters.guardrails === "Only failures" && failed(check)));
    if (!visible.length) continue;

    const owner = input ? first : !stopped ? after : undefined;
    const message = owner && ownerMessage(owner, messages);
    if (filters.messages === "Show" && message) {
      attach(messageChecks, message.id, visible);
      continue;
    }
    if (filters.tools !== "Hide" && !stopped) {
      const executed = transferTool || tools.find(tool => proposed.has(tool.id));
      if (executed) {
        attach(toolChecks, executed.id, visible);
        continue;
      }
    }

    const evidence = input ? [first] : [after, transfer];
    const text = evidence.find(check => check && !check.contentUnavailable && check.checkedText)?.checkedText;
    const showText = filters.messages === "Show" && (input || !!after || !!text || !transfer);
    const showTools = filters.tools !== "Hide" && (!!transfer || proposed.size > 0);
    if (!showText && !showTools) continue;
    const label = input && text ? "Checked input" : stopped && text && showText ? "Unsent" : stopped && showTools ? "Not run" :
      !stopped && text && showText ? "Checked candidate" : "Private activity";
    privateRows.push({
      id, participantId: input ? first.sourceParticipantId ?? first.participantId : first.participantId, occurredAt: after?.occurredAt ?? first.occurredAt,
      checks: visible, blocked, text: showText ? text : undefined, label,
      tools: showTools ? [...proposed.values()].map(tool =>
        tool.id === invocation && transfer && !transfer.contentUnavailable
          ? {...tool, requestedDestination: transfer.requestedDestination} : tool) : [],
    });
  }
  return {messageChecks, toolChecks, privateRows, withheldTools};
}

export function revealGuardrail(filters: HistoryFilters, check: GuardrailEvaluation): HistoryFilters {
  return {
    ...filters,
    guardrails: failed(check) && filters.guardrails !== "All" ? "Only failures" : "All",
    messages: check.event === "before_outgoing_transfer" ? filters.messages : "Show",
    tools: check.event === "before_outgoing_transfer" && filters.tools === "Hide" ? "Only calls" : filters.tools,
  };
}
