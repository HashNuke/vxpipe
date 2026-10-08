import { catalogCapabilities } from "../modelCatalog";
import type { CallSpecSource, SourceIssue } from "./types";
import { record } from "./validationFields";

export type IssueLocation = { nodeId: string; tab: string; field: string[]; label: string };
export type AuthoringError = { code: string; path?: string[]; reason?: string };
export type ActionResult = { status?: number; revision?: number; error?: AuthoringError; clientIssues?: SourceIssue[] };
export type ActionFeedback = {
  tone: "success" | "error";
  message: string;
  persistent: boolean;
  action?: "show" | "services" | "reload" | "retry";
  location?: IssueLocation | null;
  issue?: AuthoringError;
  disableSave?: boolean;
  disableAuthoring?: boolean;
  sessionExpired?: boolean;
};
const capabilityNames: Record<string, string> = {
  speech_to_text: "Speech to text", output_speech_to_text: "Output speech to text",
  text_to_speech: "Text to speech", speech_to_speech: "Speech to speech", model_inference: "Model inference",
};
const participantFields: Record<string, [string, string]> = {
  type: ["prompt", "Participant type"], description: ["prompt", "Description"], prompt: ["prompt", "Prompt"],
  first_message: ["prompt", "First message"], connection: ["connection", "Connection"],
  transfer_notice: ["connection", "Private briefing"], capabilities: ["voice", "Voice and model"],
  transfers: ["transfers", "Transfer destinations"], transfer_history: ["transfers", "Transfer history"],
  variable_permissions: ["variables", "Section permissions"], tools: ["tools", "Tools"], while_present: ["presence", "Presence"],
};
const settingsFields: Record<string, [string, string]> = {
  name: ["direction", "Name"], schema_version: ["advanced", "Schema version"], participants: ["direction", "Participants"],
  defaults: ["defaults", "Voice and model"], call_variables: ["variables", "Variables"],
  media_policy: ["media", "Media and recording"], wait_sounds: ["wait", "Wait sounds"],
  tool_visibility: ["advanced", "Tool visibility"], tool_visibility_overrides: ["advanced", "Tool visibility"],
  limits: ["advanced", "Call limits"], transfer_policy: ["advanced", "Transfer timeout"],
};

export function locateIssue(source: CallSpecSource, path: string[]): IssueLocation | null {
  const [root, key, field] = path;
  const entry = source.incoming_call?.caller ?? source.outgoing_call?.callee ?? source.entry_caller;
  const entryLabel = source.outgoing_call ? "Callee" : "Caller";
  const location = (nodeId: string, tab: string, label: string): IssueLocation => ({ nodeId, tab, field: path, label });
  if (!root) return location("$settings", "direction", "Call settings › Direction");
  if (root === "participants" && key) {
    if (!Object.hasOwn(source.participants, key)) return null;
    const participant = source.participants[key]!;
    const nodeId = key === entry ? "$entry" : key;
    const title = key === entry ? entryLabel : `${participant.type === "agent" ? "Agent" : "Human"} ${key}`;
    if (!field) return location(nodeId, participant.type === "agent" ? "prompt" : "connection", `${title} › Key`);
    if (!Object.hasOwn(participantFields, field)) return null;
    const [tab, label] = participantFields[field]!;
    if (field === "capabilities" && path[3] && !catalogCapabilities.some((kind) => kind === path[3])) return null;
    return location(nodeId, participant.type === "human" && tab === "prompt" ? "connection" : tab, `${title} › ${field === "capabilities" && path[3] ? capabilityNames[path[3]] : label}`);
  }
  if (root === "incoming_call" || root === "outgoing_call") {
    if (key === "ring_timeout_ms") return location("$entry", "connection", `${entryLabel} › Ring timeout`);
    if (key && !["caller", "callee", "handled_by"].includes(key)) return null;
    return location("$settings", "direction", `Call settings › ${key === "handled_by" ? "Handled by" : "Direction"}`);
  }
  if (root === "opening_audio") return location("$entry", "connection", `${entryLabel} › Opening audio`);
  if (!Object.hasOwn(settingsFields, root)) return null;
  const [tab, label] = settingsFields[root]!;
  if (root === "defaults" && key === "capabilities" && field) {
    if (!Object.hasOwn(capabilityNames, field)) return null;
    return location("$settings", tab, `Call settings › ${capabilityNames[field]}`);
  }
  return location("$settings", tab, `Call settings › ${label}`);
}

export function actionOutcome(source: CallSpecSource, action: "save" | "publish", result: ActionResult): ActionFeedback {
  const verb = action === "save" ? "saving" : "publishing";
  if (result.clientIssues?.length) {
    const issue = result.clientIssues[0]!;
    return { tone: "error", persistent: true, message: `Fix ${result.clientIssues.length} ${result.clientIssues.length === 1 ? "issue" : "issues"} before ${verb}`, action: "show", issue, location: locateIssue(source, issue.path) };
  }
  if (result.status && result.status >= 200 && result.status < 300) return {
    tone: "success", persistent: false, message: `${action === "save" ? "Saved as" : "Published"} revision ${result.revision}`,
  };
  const error = result.error;
  const path = error?.path ?? [];
  const location = error?.path ? locateIssue(source, path) : null;
  const failure = (message: string, next?: ActionFeedback["action"], extra?: Partial<ActionFeedback>): ActionFeedback => ({ tone: "error", persistent: true, message, action: next, ...extra });
  const placed = { issue: error, location };
  if (result.status === 401) return failure("Your session expired. Changes in this tab are kept until you leave the page", undefined, { sessionExpired: true });
  switch (error?.code) {
    case "invalid_call_spec":
    case "unsupported_call_plan":
    case "call_spec_not_publishable":
      return failure(`Couldn't ${action}: ${location ? `${location.label} ` : ""}${error.reason || "The call spec could not be validated."}`, "show", placed);
    case "provider_credential_unavailable":
      return failure(`No usable ${selectionName(source, path, "provider") ?? "selected provider"} credential for this tenant`, "services", placed);
    case "provider_service_forbidden":
      return failure(`This tenant can't use ${selectionName(source, path, "provider") ?? "selected provider"}`, "services", placed);
    case "telephony_caller_id_missing":
      return failure(`${selectionName(source, path, "service") ?? "Selected phone service"} has no outbound caller ID number`, "services", placed);
    case "invalid_telephony_route":
      return failure(`The phone number isn't routable through ${selectionName(source, path, "service") ?? "the selected phone service"}`, "show", placed);
    case "private_call_spec_material":
      return failure(`Remove credentials or secrets from ${location?.label ?? "the call spec"}`, "show", placed);
    case "revision_conflict":
      return failure("This spec changed while saving. Reload to see the latest revision", "reload");
    case "call_spec_not_found":
      return failure("This call spec no longer exists", undefined, { disableSave: true });
    case "authoring_forbidden":
      return failure("You don't have permission to change call specs", undefined, { disableAuthoring: true });
    case "invalid_request":
      return failure(`Couldn't ${action}: the editor sent an invalid request`);
    default:
      return failure(`Couldn't ${action}. Try again`, "retry");
  }
}

function selectionName(source: CallSpecSource, path: string[], name: "provider" | "service"): string | undefined {
  let value: unknown = source;
  for (const part of path) {
    if (!record(value)) return undefined;
    if (typeof value[name] === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value[name])) return value[name];
    if (!Object.hasOwn(value, part)) return undefined;
    value = value[part];
  }
  if (record(value) && typeof value[name] === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value[name])) return value[name];
  return undefined;
}
