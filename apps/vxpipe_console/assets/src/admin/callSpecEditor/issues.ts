import { actionOutcome, locateIssue, type ActionResult } from "./errorPresentation";
import type { CallSpecSource, SourceIssue } from "./types";

export function mergeIssues(client: SourceIssue[], backend?: SourceIssue): SourceIssue[] {
  if (!backend || client.some((issue) => issue.code === backend.code && issue.reason === backend.reason && JSON.stringify(issue.path) === JSON.stringify(backend.path))) return client;
  return [...client, backend];
}
export function issueCounts(source: CallSpecSource, issues: SourceIssue[]) {
  const nodes = new Map<string, number>();
  const tabs = new Map<string, Map<string, number>>();
  for (const issue of issues) {
    const location = locateIssue(source, issue.path);
    if (!location) continue;
    nodes.set(location.nodeId, (nodes.get(location.nodeId) ?? 0) + 1);
    const counts = tabs.get(location.nodeId) ?? new Map<string, number>();
    counts.set(location.tab, (counts.get(location.tab) ?? 0) + 1);
    tabs.set(location.nodeId, counts);
  }
  return { nodes: Object.fromEntries(nodes), tabs: Object.fromEntries([...tabs].map(([node, counts]) => [node, Object.fromEntries(counts)])) };
}
const fieldCodes = new Set(["invalid_call_spec", "unsupported_call_plan", "call_spec_not_publishable", "provider_credential_unavailable", "provider_service_forbidden", "telephony_caller_id_missing", "invalid_telephony_route", "private_call_spec_material"]);
export function backendIssue(source: CallSpecSource, result: ActionResult): SourceIssue | undefined {
  const error = result.error;
  if (result.status === 401 || !error || !fieldCodes.has(error.code)) return undefined;
  return { code: error.code, path: error.path ?? [], reason: error.code === "private_call_spec_material" ? actionOutcome(source, "save", result).message : error.reason || actionOutcome(source, "save", result).message };
}
export function retainBackendIssue(issue: SourceIssue | undefined, previous: CallSpecSource, next: CallSpecSource): SourceIssue | undefined {
  return issue && JSON.stringify(pathValue(previous, issue.path)) === JSON.stringify(pathValue(next, issue.path)) ? issue : undefined;
}
function pathValue(source: CallSpecSource, path: string[]): unknown {
  let value: unknown = source;
  for (const part of path) {
    if (value === null || typeof value !== "object" || !Object.hasOwn(value, part)) return undefined;
    value = (value as Record<string, unknown>)[part];
  }
  return value;
}
