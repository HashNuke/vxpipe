import { Fields, record, type ObjectValue } from "./validationFields";

const common = ["type", "description", "capabilities", "while_present"];
const agentFields = ["prompt", "first_message", "tools", "transfers", "transfer_history", "variable_permissions", "guardrails"];
const humanFields = ["connection", "transfer_notice"];
const reservedTools = ["transfer", "read_variables", "update_variables", "update_variable"];

export function validateParticipant(fields: Fields, source: ObjectValue, key: string, value: unknown, participants: ObjectValue): void {
  const path = ["participants", key];
  fields.identifier(key, path);
  const item = fields.object(value, path);
  fields.enumeration(item.type, [...path, "type"], ["agent", "human"]);
  const allowed = [...common, ...(item.type === "agent" ? agentFields : humanFields)];
  for (const field of Object.keys(item)) if (!allowed.includes(field)) fields.issue([...path, field], "is not supported for this participant type");
  fields.text(item.description, [...path, "description"], 1024, true);
  if (item.type === "human") {
    fields.text(item.transfer_notice, [...path, "transfer_notice"], 4096, true);
    connection(fields, source, key, item.connection, [...path, "connection"]);
  } else if (item.type === "agent") {
    if (typeof item.prompt !== "string" || Array.from(item.prompt.trim()).length < 100) {
      fields.issue([...path, "prompt"], "Write at least 100 characters of instructions for this agent.");
    } else if (new TextEncoder().encode(item.prompt).length > 32768) {
      fields.issue([...path, "prompt"], "This prompt is too long. Shorten the instructions and try again.");
    }
    firstMessage(fields, item, path);
    tools(fields, item, path);
    transfers(fields, item, key, path, participants);
    history(fields, item, path);
    guardrails(fields, source, item, path);
  }
}

function firstMessage(fields: Fields, item: ObjectValue, path: string[]): void {
  if (item.first_message === undefined) return;
  const location = [...path, "first_message"];
  const first = fields.object(item.first_message, location, ["mode", "text"]);
  fields.enumeration(first.mode, [...location, "mode"], ["wait_for_input", "generated", "fixed"]);
  if (first.mode === "fixed") fields.text(first.text, [...location, "text"], 4096);
  else if (Object.hasOwn(first, "text")) fields.issue([...location, "text"], "is only supported for fixed mode");
}

function tools(fields: Fields, item: ObjectValue, path: string[]): void {
  if (item.tools === undefined) return;
  for (const [name, value] of Object.entries(fields.object(item.tools, [...path, "tools"]))) {
    const location = [...path, "tools", name];
    fields.identifier(name, location);
    if (reservedTools.includes(name)) fields.issue(location, "collides with a platform tool name");
    const tool = fields.object(value, location, ["type", "tool", "integration", "conversation_mode"]);
    fields.enumeration(tool.type, [...location, "type"], ["host", "mcp", "platform"]);
    fields.identifier(tool.tool, [...location, "tool"]);
    if (tool.conversation_mode !== undefined) fields.enumeration(tool.conversation_mode, [...location, "conversation_mode"], ["blocking", "non_blocking"]);
    if (tool.type === "mcp") fields.identifier(tool.integration, [...location, "integration"]);
    else if (Object.hasOwn(tool, "integration")) fields.issue([...location, "integration"], "is only supported for MCP tools");
  }
}

function transfers(fields: Fields, item: ObjectValue, key: string, path: string[], participants: ObjectValue): void {
  if (item.transfers === undefined) return;
  if (!Array.isArray(item.transfers)) { fields.issue([...path, "transfers"], "must be an array of participant references"); return; }
  const seen = new Set<string>();
  item.transfers.forEach((target: unknown, index) => {
    const location = [...path, "transfers", String(index)];
    if (!fields.identifier(target, location)) return;
    if (seen.has(target)) fields.issue(location, "must not be duplicated");
    seen.add(target);
    if (!Object.hasOwn(participants, target)) { fields.issue(location, "must reference a participant"); return; }
    if (target === key) fields.issue(location, "must reference another participant");
    const destination = participants[target];
    if (!record(destination) || destination.type === "agent") return;
    const connection = destination.connection;
    const valid = record(connection) && ((connection.service === "web" && connection.mode === "receive" && connection.admission === "transfer") ||
      (connection.service !== "web" && connection.mode === "dial" && (connection.admission === "transfer" || connection.admission === undefined)));
    if (!valid) fields.issue(location, "must reference an agent or transfer-admission human participant");
  });
}

function history(fields: Fields, item: ObjectValue, path: string[]): void {
  if (item.transfer_history === undefined || item.transfer_history === null) return;
  const location = [...path, "transfer_history"];
  const history = fields.object(item.transfer_history, location, ["mode", "turns"]);
  fields.enumeration(history.mode, [...location, "mode"], ["fresh", "all_spoken", "last_n_spoken", "selected"]);
  if (history.mode === "last_n_spoken") fields.integer(history.turns, [...location, "turns"], 1, Number.MAX_SAFE_INTEGER);
  else if (Object.hasOwn(history, "turns")) fields.issue([...location, "turns"], "is only supported for last_n_spoken mode");
}

function guardrails(fields: Fields, source: ObjectValue, item: ObjectValue, path: string[]): void {
  if (item.guardrails === undefined) return;
  const location = [...path, "guardrails"];
  if (source.schema_version !== "20261128.01") {
    fields.issue(location, "is not supported in this schema version");
    return;
  }
  const value = fields.object(item.guardrails, location, ["before_turn", "after_turn", "before_outgoing_transfer"]);
  const seen = new Set<string>();
  for (const event of ["before_turn", "after_turn", "before_outgoing_transfer"] as const) {
    if (value[event] === undefined) continue;
    const eventPath = [...location, event];
    if (!Array.isArray(value[event])) { fields.issue(eventPath, "must be a list of questions"); continue; }
    const questions = value[event] as unknown[];
    if (questions.length > 32) fields.issue(eventPath, "must contain at most 32 questions");
    let bytes = 0;
    questions.forEach((entry, index) => {
      const questionPath = [...eventPath, String(index)];
      const question = fields.object(entry, questionPath, ["id", "question", "required_answer", "probability_threshold", "response"]);
      if (question.id !== undefined && (typeof question.id !== "string" || !/^[a-z][a-z0-9_]{0,63}$/.test(question.id))) {
        fields.issue([...questionPath, "id"], "must match [a-z][a-z0-9_]{0,63}");
      } else if (typeof question.id === "string") {
        if (seen.has(question.id)) fields.issue([...questionPath, "id"], "must be unique within the participant");
        seen.add(question.id);
      }
      if (typeof question.question !== "string" || !question.question.trim() || new TextEncoder().encode(question.question).length > 1024) {
        fields.issue([...questionPath, "question"], "must be a non-empty string of at most 1024 bytes");
      } else {
        bytes += new TextEncoder().encode(question.question).length;
      }
      if (question.required_answer !== "yes" && question.required_answer !== "no") {
        fields.issue([...questionPath, "required_answer"], question.required_answer === undefined ? "is required" : "must be a supported value");
      }
      if (question.probability_threshold !== undefined) {
        const threshold = question.probability_threshold;
        const valid = typeof threshold === "number" && Number.isFinite(threshold) && threshold >= 0 && threshold <= 1 &&
          /^(0(\.\d{1,2})?|1(\.0{1,2})?)$/.test(String(threshold));
        if (!valid) fields.issue([...questionPath, "probability_threshold"], "must be between 0.00 and 1.00 in hundredth increments");
      }
      if (question.response !== undefined && (typeof question.response !== "string" || new TextEncoder().encode(question.response).length > 1024)) {
        fields.issue([...questionPath, "response"], "must be a string of at most 1024 bytes");
      }
    });
    if (bytes > 16384) fields.issue(eventPath, "must contain at most 16384 bytes of question text");
    if ((event === "before_turn" || event === "after_turn") && questions.length > 0) {
      const capabilities = record(item.capabilities) ? item.capabilities : {};
      const defaults = record(source.defaults) && record(source.defaults.capabilities) ? source.defaults.capabilities : {};
      const speechToSpeech = (capabilities as ObjectValue).speech_to_speech ?? (defaults as ObjectValue).speech_to_speech;
      if (speechToSpeech) fields.issue(eventPath, "is not supported for speech-to-speech agents");
    }
  }
}

function connection(fields: Fields, source: ObjectValue, key: string, value: unknown, path: string[]): void {
  const item = fields.object(value, path, ["service", "mode", "admission", "number", "number_from_variable"]);
  const callee = record(source.outgoing_call) && source.outgoing_call.callee === key;
  fields.identifier(item.service, [...path, "service"]);
  fields.enumeration(item.mode, [...path, "mode"], ["receive", "dial"]);
  if (item.mode === "receive") fields.enumeration(item.admission, [...path, "admission"], ["start_call", "transfer"]);
  else if (item.admission !== undefined) fields.enumeration(item.admission, [...path, "admission"], [callee ? "start_call" : "transfer"]);
  if (item.service === "web") {
    if (item.mode === "dial") fields.issue([...path, "mode"], "dial mode requires a configured telephony service");
    for (const name of ["number", "number_from_variable"]) if (Object.hasOwn(item, name)) fields.issue([...path, name], "is not supported for web connections");
    return;
  }
  const variable = Object.hasOwn(item, "number_from_variable");
  const number = Object.hasOwn(item, "number");
  if (variable) {
    const location = [...path, "number_from_variable"];
    if (callee) fields.issue(location, "is not supported for an outgoing callee; use number or the request's to");
    else if (item.mode !== "dial") fields.issue(location, "is only supported for dial mode");
    else if (number) fields.issue(location, "must not be combined with number");
    const ref = fields.object(item.number_from_variable, location, ["section", "variable"]);
    fields.identifier(ref.section, [...location, "section"]);
    fields.identifier(ref.variable, [...location, "variable"]);
  }
  if (number || (!callee && !variable)) fields.phone(item.number, [...path, "number"]);
}
