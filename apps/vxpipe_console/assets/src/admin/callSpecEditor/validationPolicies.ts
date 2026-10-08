import { catalogCapabilities } from "../modelCatalog";
import { Fields, record, type ObjectValue } from "./validationFields";

export function validatePolicies(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  if (source.defaults !== undefined) {
    const defaults = fields.object(source.defaults, ["defaults"], ["capabilities"]);
    if (defaults.capabilities !== undefined) capabilities(fields, defaults.capabilities, ["defaults", "capabilities"]);
  }
  if (source.media_policy !== undefined) media(fields, source.media_policy, ["media_policy"], participants);
  for (const [key, value] of Object.entries(participants)) {
    if (!record(value)) continue;
    if (value.capabilities !== undefined) capabilities(fields, value.capabilities, ["participants", key, "capabilities"]);
    if (value.while_present !== undefined) media(fields, value.while_present, ["participants", key, "while_present"], participants);
  }
  if (source.wait_sounds !== undefined && source.wait_sounds !== null) {
    const sounds = fields.object(source.wait_sounds, ["wait_sounds"], ["call_setup", "transfer_to_agent", "transfer_to_human", "transfer_joining"]);
    for (const [slot, value] of Object.entries(sounds)) if (value !== null) audioUrl(fields, value, ["wait_sounds", slot], false);
  }
  opening(fields, source.opening_audio);
  visibility(fields, source, participants);
}

function capabilities(fields: Fields, value: unknown, path: string[]): void {
  const selections = fields.object(value, path, catalogCapabilities);
  for (const [kind, selection] of Object.entries(selections)) capability(fields, selection, [...path, kind]);
}

function capability(fields: Fields, value: unknown, path: string[]): void {
  const selection = fields.object(value, path, ["provider", "model", "credential_name", "options", "provider_options"]);
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

function opening(fields: Fields, value: unknown): void {
  if (value === undefined || value === null) return;
  const path = ["opening_audio"];
  const item = fields.object(value, path, ["type", "url", "text", "text_to_speech"]);
  fields.enumeration(item.type, [...path, "type"], ["text", "file_url"]);
  if (item.type === "text") {
    if (Object.hasOwn(item, "url")) fields.issue([...path, "url"], "is not supported for this opening audio type");
    fields.text(item.text, [...path, "text"], 4096);
    capability(fields, item.text_to_speech, [...path, "text_to_speech"]);
  } else if (item.type === "file_url") {
    for (const name of ["text", "text_to_speech"]) if (Object.hasOwn(item, name)) fields.issue([...path, name], "is not supported for this opening audio type");
    audioUrl(fields, item.url, [...path, "url"], true);
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
