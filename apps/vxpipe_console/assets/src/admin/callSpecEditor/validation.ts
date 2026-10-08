import type { SourceIssue } from "./types";
import { Fields, record, type ObjectValue } from "./validationFields";
import { validatePolicies } from "./validationPolicies";
import { validateVariables } from "./validationVariables";
import { validateParticipant } from "./validationParticipants";

const rootFields = ["schema_version", "name", "incoming_call", "outgoing_call", "entry_caller", "entry_receiver", "participants", "defaults", "opening_audio", "wait_sounds", "media_policy", "call_variables", "transfer_policy", "tool_visibility", "tool_visibility_overrides", "limits"];

export function validateSource(value: unknown): SourceIssue[] {
  const fields = new Fields();
  const source = fields.object(value, [], rootFields);
  fields.enumeration(source.schema_version, ["schema_version"], ["20261004.01", "20260915.01"]);
  fields.text(source.name, ["name"], 256, true);
  const participants = fields.object(source.participants, ["participants"]);
  if (!Object.keys(participants).length) fields.issue(["participants"], "must be a non-empty object");
  for (const [key, participant] of Object.entries(participants)) validateParticipant(fields, source, key, participant, participants);
  direction(fields, source, participants);
  validatePolicies(fields, source, participants);
  validateVariables(fields, source, participants);
  if (source.transfer_policy !== undefined && source.transfer_policy !== null) {
    const policy = fields.object(source.transfer_policy, ["transfer_policy"], ["attempt_timeout_ms"]);
    if (Object.hasOwn(policy, "attempt_timeout_ms")) fields.integer(policy.attempt_timeout_ms, ["transfer_policy", "attempt_timeout_ms"], 1000, 120000);
  }
  if (source.limits !== undefined) {
    const limits = fields.object(source.limits, ["limits"], ["max_duration_ms"]);
    if (Object.hasOwn(limits, "max_duration_ms")) fields.integer(limits.max_duration_ms, ["limits", "max_duration_ms"], 1000, 86400000);
  }
  return fields.issues;
}

function direction(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  const legacy = source.schema_version === "20260915.01";
  const outgoing = Object.hasOwn(source, "outgoing_call");
  const incoming = Object.hasOwn(source, "incoming_call");
  if (!legacy && outgoing === incoming) { fields.issue([], "must declare exactly one of incoming_call or outgoing_call"); return; }
  for (const key of legacy ? ["incoming_call", "outgoing_call"] : ["entry_caller", "entry_receiver"]) {
    if (Object.hasOwn(source, key)) fields.issue([key], "is not supported in this schema version");
  }
  const block = outgoing ? "outgoing_call" : "incoming_call";
  const callerField = outgoing ? "callee" : "caller";
  const spec = legacy ? source : fields.object(source[block], [block], outgoing ? ["callee", "handled_by", "ring_timeout_ms"] : ["caller", "handled_by"]);
  const entry = spec[legacy ? "entry_caller" : callerField];
  const handler = spec[legacy ? "entry_receiver" : "handled_by"];
  const entryPath = legacy ? ["entry_caller"] : [block, callerField];
  const handlerPath = legacy ? ["entry_receiver"] : [block, "handled_by"];
  for (const [key, path] of [[entry, entryPath], [handler, handlerPath]] as const) {
    if (fields.identifier(key, path) && !Object.hasOwn(participants, key)) fields.issue(path, "must reference a participant");
  }
  if (entry === handler) fields.issue(handlerPath, "must differ from the caller or callee");
  const caller = typeof entry === "string" && Object.hasOwn(participants, entry) ? participants[entry] : undefined;
  const receiver = typeof handler === "string" && Object.hasOwn(participants, handler) ? participants[handler] : undefined;
  if (record(caller) && caller.type !== "human") fields.issue(entryPath, "must reference a human participant");
  if (outgoing && record(receiver) && receiver.type !== "agent") fields.issue(handlerPath, "must reference an agent participant");
  if (!legacy && record(caller) && record(caller.connection)) {
    const connection = caller.connection;
    const valid = outgoing
      ? connection.service !== "web" && connection.mode === "dial" && (connection.admission === undefined || connection.admission === "start_call")
      : connection.mode === "receive" && connection.admission === "start_call";
    if (!valid) fields.issue(entryPath, "must have the direction's initial connection intent");
  }
  if (outgoing && Object.hasOwn(spec, "ring_timeout_ms")) fields.integer(spec.ring_timeout_ms, [block, "ring_timeout_ms"], 5000, 60000);
}
