import type { CallDetailsTimelineEntity } from "@vxpipe/core";
import { inspectionFixture, type GuardrailCheck, type GuardrailScenario } from "./guardrailInspectionFixtures";
import type { HistoryFilters } from "./GuardrailHistoryFilters";

type Tool = {id: string; name: string; arguments: Record<string, string>};
export type Annotation = {
  anchor: "message" | "tool" | "activity"; label: string; checks: GuardrailCheck[]; tools: Tool[]; unsent?: boolean; toolOnly?: boolean; blocked: boolean;
};

// Fixture message times are unique. Evaluation ownership comes from the turn or proposal ID.
export function historyTimeline(scenario: GuardrailScenario, start: number, filters: HistoryFilters) {
  const { messages, checks } = inspectionFixture(scenario);
  const timeline: CallDetailsTimelineEntity[] = [];
  const annotations = new Map<string, Annotation>();
  const time = (step: number) => new Date(start + step * 1_000).toISOString();
  const whenVisible = (owned: GuardrailCheck[]) => owned.filter(check =>
    filters.guardrails === "All" || (filters.guardrails === "Only failures" && check.status !== "Passed"));

  function message(id: string, turnId: string, participantId: string, text: string, occurredAt: string) {
    timeline.push({ kind: "message", revision: 1, id, value: {id, turnId, participantId, occurredAt, text, state: "final"} });
  }

  // Private tool-only entries have their own history activity and never become transcript text.
  function toolActivity(id: string, occurredAt: string, label: string) {
    timeline.push({ kind: "activity", revision: 1, id, value: {id, occurredAt, kind: "call", text: label} });
  }

  for (const [i, msg] of messages.entries()) {
    const owned = checks.filter(check => check.messageId === msg.id && check.turn === msg.turn);
    const proposalIds = [...new Set(owned.flatMap(c => c.proposalId ? [c.proposalId] : []))];
    for (const [ordinal, proposal] of proposalIds.entries()) {
      const group = owned.filter(check => check.proposalId === proposal);
      const visible = whenVisible(group);
      const evidence = group.find(c => c.evidence?.rejectedDraft)?.evidence;
      const tools = filters.tools ? group.find(c => c.evidence?.proposedTools)?.evidence?.proposedTools ?? [] : [];
      const speech = filters.messages && evidence?.rejectedDraft;
      if (!visible.length || (!speech && !tools.length)) continue;
      const at = time(4 * i + 2 + ordinal / 10);
      if (speech) message(proposal, msg.turn, msg.participantId, speech, at);
      else toolActivity(proposal, at, "Proposed tools");
      annotations.set(at, {anchor: speech ? "message" : "activity", label: speech || "Proposed tools", checks: visible, tools, unsent: !!speech, toolOnly: !speech, blocked: true});
    }
    if (filters.messages) {
      const at = time(4 * i + 3);
      message(msg.id, msg.turn, msg.participantId, msg.text, at);
      const visible = whenVisible(owned.filter(c => !c.proposalId));
      if (visible.length) annotations.set(at, {anchor: "message", label: msg.text, checks: visible, tools: [], blocked: visible.some(c => c.status === "Blocked")});
    }
  }
  for (const [i, check] of checks.filter(c => c.turn === null && c.transfer).entries()) {
    if (!filters.tools || (!check.completedTransfer && !whenVisible([check]).length)) continue;
    const at = time(4 * messages.length + 3 + i);
    const visible = whenVisible([check]);
    const transfer = check.transfer!;
    if (check.completedTransfer) {
      timeline.push({kind: "tool-call", revision: 1, id: transfer.id, value: {
        id: transfer.id, name: "transfer", occurredAt: at, status: "completed",
        ...(filters.toolDetails && {request: {destination: transfer.destination}, response: check.completedTransfer}),
      }});
      if (visible.length) annotations.set(at, {anchor: "tool", label: "transfer", checks: visible, tools: [], blocked: false});
    } else {
      const label = "Transfer to " + transfer.destination;
      toolActivity(check.id, at, label);
      annotations.set(at, {anchor: "activity", label, checks: visible, tools: [], toolOnly: true, blocked: check.status === "Blocked"});
    }
  }
  return {timeline, annotations};
}
