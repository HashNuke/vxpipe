import type { Voice, VoiceCatalogClient, VoiceCatalogDescriptor, VoiceFilter, VoiceScope } from "../voiceCatalog";
import type { EditorFetch } from "./editor-api";
import { record } from "./validationFields";

const text = (value: unknown, limit: number): value is string => typeof value === "string" && value.length <= limit;
const voice = (value: unknown): value is Voice => record(value) && text(value.id, 128) && !!value.id && text(value.name, 256) &&
  (value.description === undefined || text(value.description, 4096)) && Array.isArray(value.attributes) && value.attributes.length <= 20 &&
  value.attributes.every(attribute => record(attribute) && text(attribute.key, 128) && text(attribute.label, 128) && text(attribute.value, 128));
const filter = (value: unknown): value is VoiceFilter => record(value) && text(value.key, 128) && text(value.label, 128) &&
  (["text", "boolean"].includes(String(value.type)) || (value.type === "select" || value.type === "multi_select") &&
    Array.isArray(value.options) && value.options.length <= 200 && value.options.every(option => record(option) && text(option.value, 128) && text(option.label, 128)));
const invalid = () => new Error("Invalid voice catalog response");

/** Tenant-scoped client; every request reauthorizes the selected effective connection. */
export function createVoiceCatalogClient(tenant: string, fetch: EditorFetch): VoiceCatalogClient {
  async function get(scope: VoiceScope, suffix: string, query: Record<string, string>, signal: AbortSignal) {
    const params = new URLSearchParams({ capability: scope.capability, model: scope.model, credential_name: scope.credential_name ?? "default", ...query });
    const path = `/admin/api/tenants/${encodeURIComponent(tenant)}/providers/${encodeURIComponent(scope.provider)}/voices${suffix}?${params}`;
    const response = await fetch(path, { signal, credentials: "same-origin", cache: "no-store", headers: { accept: "application/json" } });
    if (!response.ok) throw new Error("Voice catalog access is unavailable");
    const body: unknown = await response.json();
    if (!record(body)) throw invalid();
    return body;
  }
  return {
    async describe(scope, signal) {
      const body = await get(scope, "/descriptor", {}, signal);
      if (!text(body.providerName, 256) || !text(body.modelName, 256) || typeof body.search !== "boolean" ||
        !Array.isArray(body.filters) || body.filters.length > 20 || !body.filters.every(filter)) throw invalid();
      return body as VoiceCatalogDescriptor;
    },
    async list(scope, query, signal) {
      const params: Record<string, string> = { search: query.search, filters: JSON.stringify(query.filters) };
      if (query.cursor !== null) params.cursor = query.cursor;
      const body = await get(scope, "", params, signal);
      if (!Array.isArray(body.voices) || body.voices.length > 100 || !body.voices.every(voice) ||
        !(body.nextCursor === null || text(body.nextCursor, 2048)) ||
        !(body.total === undefined || Number.isSafeInteger(body.total) && Number(body.total) >= 0)) throw invalid();
      return { voices: body.voices, nextCursor: body.nextCursor, ...(typeof body.total === "number" ? { total: body.total } : {}) };
    },
    async get(scope, id, signal) {
      if (!id) return null;
      const body = await get(scope, `/${encodeURIComponent(id)}`, {}, signal);
      if (body.voice !== null && (!voice(body.voice) || body.voice.id !== id)) throw invalid();
      return body.voice;
    },
  };
}
