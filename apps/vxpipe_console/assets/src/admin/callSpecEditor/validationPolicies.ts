import { catalogCapabilities } from "../modelCatalog";
import { Fields, record, type ObjectValue } from "./validationFields";

export function validatePolicies(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  if (source.defaults !== undefined) {
    const defaults = fields.object(source.defaults, ["defaults"], ["capabilities"]);
    if (defaults.capabilities !== undefined) {
      capabilities(fields, defaults.capabilities, ["defaults", "capabilities"]);
      if (source.schema_version !== "20261128.01" && record(defaults.capabilities) && Object.hasOwn(defaults.capabilities, "decisions")) {
        fields.issue(["defaults", "capabilities", "decisions"], "is not supported in this schema version");
      }
    }
  }
  if (source.media_policy !== undefined) media(fields, source.media_policy, ["media_policy"], participants);
  for (const [key, value] of Object.entries(participants)) {
    if (!record(value)) continue;
    if (value.capabilities !== undefined) {
      capabilities(fields, value.capabilities, ["participants", key, "capabilities"]);
      if (record(value.capabilities) && Object.hasOwn(value.capabilities, "decisions")) {
        fields.issue(["participants", key, "capabilities", "decisions"], "Change the Decisions model in Call settings → Models.");
      }
    }
    if (value.while_present !== undefined) media(fields, value.while_present, ["participants", key, "while_present"], participants);
  }
  if (source.wait_sounds !== undefined && source.wait_sounds !== null) {
    const sounds = fields.object(source.wait_sounds, ["wait_sounds"], ["call_setup", "transfer_to_agent", "transfer_to_human", "transfer_joining"]);
    for (const [slot, value] of Object.entries(sounds)) if (value !== null) audioUrl(fields, value, ["wait_sounds", slot], false);
  }
  opening(fields, source);
  visibility(fields, source, participants);
  guardrailDecisions(fields, source, participants);
}

function capabilities(fields: Fields, value: unknown, path: string[]): void {
  const selections = fields.object(value, path, catalogCapabilities);
  for (const [kind, selection] of Object.entries(selections)) capability(fields, selection, [...path, kind]);
}

function capability(fields: Fields, value: unknown, path: string[]): void {
  const isHumanSTT = path.at(-1) === "speech_to_text";
  const selection = fields.object(value, path, ["provider", "model", "credential_name", "options", "provider_options", ...(path.at(-1) === "model_inference" ? [] : ["languages"]), ...(isHumanSTT ? ["vad"] : [])]);
  const legacyHints = selection.languages;
  if (legacyHints !== undefined && (!Array.isArray(legacyHints) || !legacyHints.every(code => typeof code === "string" && /^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$/i.test(code)) || new Set(legacyHints).size !== legacyHints.length)) {
    fields.issue([...path, "languages"], "must list distinct language tags");
  }
  if (isHumanSTT && Object.hasOwn(selection, "vad") && typeof selection.vad !== "boolean") fields.issue([...path, "vad"], "must be a boolean");
  fields.text(selection.provider, [...path, "provider"], 256);
  fields.text(selection.model, [...path, "model"], 256);
  if (selection.credential_name !== undefined) {
    if (selection.provider === "morse" || selection.provider === "fixture") fields.issue([...path, "credential_name"], "is not supported for a local provider");
    else fields.identifier(selection.credential_name, [...path, "credential_name"]);
  }
  for (const name of ["options", "provider_options"]) if (selection[name] !== undefined) {
    const options = fields.object(selection[name], [...path, name]);
    if (privateData(options)) fields.issue([...path, name], "must contain only public JSON data");
  }
}

function privateData(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(privateData);
  return record(value) && Object.entries(value).some(([key, nested]) => /(?:^|_)(api_key|authorization|password|secret|token)$/i.test(key) || privateData(nested));
}

function media(fields: Fields, value: unknown, path: string[], participants: ObjectValue): void {
  const policy = fields.object(value, path, ["audio_routes", "transcript_routes", "record_audio", "save_transcripts"]);
  for (const permission of ["record_audio", "save_transcripts"]) if (Object.hasOwn(policy, permission) && typeof policy[permission] !== "boolean") fields.issue([...path, permission], "must be a boolean");
  for (const kind of ["audio_routes", "transcript_routes"]) if (policy[kind] !== undefined) {
    for (const [key, targets] of Object.entries(fields.object(policy[kind], [...path, kind]))) {
      const location = [...path, kind, key];
      fields.identifier(key, location);
      if (!Object.hasOwn(participants, key)) fields.issue(location, "must reference a participant");
      if (!Array.isArray(targets)) { fields.issue(location, "must be an array of participant references"); continue; }
      const seen = new Set<string>();
      targets.forEach((target: unknown, index) => {
        const targetPath = [...location, String(index)];
        if (!fields.identifier(target, targetPath)) return;
        if (!Object.hasOwn(participants, target)) fields.issue(targetPath, "must reference a participant");
        if (seen.has(target)) fields.issue(targetPath, "must not be duplicated");
        seen.add(target);
      });
    }
  }
}

function audioUrl(fields: Fields, value: unknown, path: string[], httpsOnly: boolean): void {
  const reason = httpsOnly ? "must be an HTTPS URL without credentials or a fragment" : "must be an absolute HTTP(S) audio-file URL without user information or fragment, or null";
  try {
    if (typeof value !== "string" || new TextEncoder().encode(value).length > 2048 || !/^https?:\/\//.test(value) || value.includes("#")) throw new Error();
    const url = new URL(value);
    if (!url.hostname || url.username || url.password || (httpsOnly && url.protocol !== "https:") || (url.port && Number(url.port) < 1)) throw new Error();
  } catch { fields.issue(path, reason); }
}

function opening(fields: Fields, source: ObjectValue): void {
  const value = source.opening_audio;
  if (value === undefined || value === null) return;
  const path = ["opening_audio"];
  const item = fields.object(value, path, ["type", "url", "text", "text_to_speech"]);
  fields.enumeration(item.type, [...path, "type"], ["text", "file_url"]);
  if (item.type === "text") {
    if (Object.hasOwn(item, "url")) fields.issue([...path, "url"], "is not supported for this opening audio type");
    fields.text(item.text, [...path, "text"], 4096);
    if (source.schema_version === "20261128.01" || source.schema_version === "20261125.01") {
      if (Object.hasOwn(item, "text_to_speech")) fields.issue([...path, "text_to_speech"], "set the opening voice in Call settings → Models");
      const defaults = record(source.defaults) && record(source.defaults.capabilities) ? source.defaults.capabilities : {};
      if (defaults.speech_to_speech || !defaults.text_to_speech) fields.issues.push({
        code: "opening_model_conflict", path: [...path, "type"], reason: "Spoken text requires a call-wide text-to-speech model before publication.",
      });
    } else capability(fields, item.text_to_speech, [...path, "text_to_speech"]);
  } else if (item.type === "file_url") {
    for (const name of ["text", "text_to_speech"]) if (Object.hasOwn(item, name)) fields.issue([...path, name], "is not supported for this opening audio type");
    audioUrl(fields, item.url, [...path, "url"], true);
  }
}

function guardrailDecisions(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  let configured = false;
  for (const value of Object.values(participants)) {
    if (!record(value) || value.type !== "agent" || !record(value.guardrails)) continue;
    for (const event of ["before_turn", "after_turn", "before_outgoing_transfer"]) {
      const questions = (value.guardrails as ObjectValue)[event];
      if (Array.isArray(questions) && questions.length > 0) configured = true;
    }
  }
  if (!configured) return;
  const defaults = record(source.defaults) ? source.defaults : {};
  const capabilities = record(defaults.capabilities) ? defaults.capabilities as ObjectValue : {};
  if (!record(capabilities.decisions)) {
    fields.issue(["defaults", "capabilities", "decisions"], "Select a Decisions model for these guardrail checks.");
  }
}

function visibility(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  const levels = ["hidden", "metadata", "full"];
  if (source.tool_visibility !== undefined) fields.enumeration(source.tool_visibility, ["tool_visibility"], levels);
  if (source.tool_visibility_overrides === undefined) return;
  for (const [key, value] of Object.entries(fields.object(source.tool_visibility_overrides, ["tool_visibility_overrides"]))) {
    const path = ["tool_visibility_overrides", key];
    const participant = Object.hasOwn(participants, key) ? participants[key] : undefined;
    if (!record(participant) || participant.type !== "agent") { fields.issue(path, "must reference an agent participant"); continue; }
    for (const [tool, level] of Object.entries(fields.object(value, path))) {
      const configured = tool === "transfer" ? Array.isArray(participant.transfers) && participant.transfers.length > 0 : record(participant.tools) && Object.hasOwn(participant.tools, tool);
      if (!configured) fields.issue([...path, tool], "must reference a configured local tool");
      fields.enumeration(level, [...path, tool], levels);
    }
  }
}
