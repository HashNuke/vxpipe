import { parseSourceJson, stringifySourceJson } from "./source-json";
import { catalogCapabilities, parseModelCatalog, type ModelCatalog } from "../modelCatalog";
import type { EditorSnapshot } from "./editor-state";
import type { AuthoringError } from "./errorPresentation";
import type { EditorLookups, PhoneNumberPage } from "./inspectorTypes";
import { parseSource } from "./source";
import type { ExecuteEditorRequest } from "./use-editor";
import { record } from "./validationFields";

export type EditorFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
export class EditorReadError extends Error {
  constructor(public readonly status: number) { super("The editor resource could not be loaded."); }
}
const revision = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0;
const names = (value: unknown): value is string[] => Array.isArray(value) && value.every((item) => typeof item === "string");

export function createEditorApi(tenant: string, csrf: string, fetch: EditorFetch) {
  const base = `/admin/api/tenants/${encodeURIComponent(tenant)}`;
  const specPath = (id: string) => `${base}/call-specs/${encodeURIComponent(id)}`;
  const options = (signal: AbortSignal): RequestInit => ({ signal, credentials: "same-origin", cache: "no-store", headers: { accept: "application/json" } });
  async function get(path: string, signal: AbortSignal): Promise<Record<string, unknown>> {
    const response = await fetch(path, options(signal));
    if (!response.ok) throw new EditorReadError(response.status);
    const body: unknown = parseSourceJson(await response.text());
    if (!record(body)) throw new Error("Invalid editor response");
    return body;
  }
  async function read(id: string, signal: AbortSignal, requestedRevision?: number): Promise<EditorSnapshot> {
    const body = await get(specPath(id) + (requestedRevision === undefined ? "" : `?revision=${requestedRevision}`), signal);
    const saved = body.call_spec;
    if (!record(saved) || saved.call_spec_id !== id || !revision(saved.revision) || !revision(saved.latest_revision) ||
      !(saved.published_revision === null || revision(saved.published_revision))) throw new Error("Invalid saved revision");
    const document = parseSource(stringifySourceJson(saved.source)!);
    if (requestedRevision !== undefined) {
      document.readOnly = true;
      document.notice = `Viewing revision ${saved.revision}. This saved revision is read-only.`;
    }
    return { document, saved: { callSpecId: id, revision: saved.revision, publishedRevision: saved.published_revision } };
  }
  const execute: ExecuteEditorRequest = async (request, signal) => {
    const writes = `/api/tenants/${encodeURIComponent(tenant)}/call-specs`;
    const target = request.callSpecId ? `${writes}/${encodeURIComponent(request.callSpecId)}` : writes;
    const path = request.action === "publish"
      ? `${target}/revisions/${request.revision}/publish`
      : target;
    const response = await fetch(path, { ...options(signal), method: request.action === "save" && request.callSpecId ? "PUT" : "POST",
      headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": csrf },
      body: stringifySourceJson(request.action === "publish" ? {} : { source: request.source }) });
    // A gateway may return an HTML login/error page. Preserve the HTTP outcome.
    const body: unknown = await response.json().catch(() => undefined);
    if (!response.ok) {
      const value = record(body) ? body.error : undefined;
      const error: AuthoringError | undefined = record(value) && typeof value.code === "string" ? {
        code: value.code,
        ...(names(value.path) ? { path: value.path } : {}),
        ...(typeof value.reason === "string" ? { reason: value.reason } : {}),
      } : undefined;
      return { status: response.status, ...(error ? { error } : {}) };
    }
    const saved = record(body) ? body.call_spec : undefined;
    if (!record(saved) || typeof saved.call_spec_id !== "string" || !saved.call_spec_id || !revision(saved.revision)) throw new Error("Invalid saved revision");
    return { status: response.status, callSpecId: saved.call_spec_id, revision: saved.revision };
  };
  async function catalog(signal: AbortSignal): Promise<ModelCatalog> {
    const entries = await Promise.all(catalogCapabilities.map(async (capability) => {
      const query = `?capability=${capability}`;
      const { providers } = await get(`${base}/providers${query}`, signal);
      if (!Array.isArray(providers) || providers.length > 32 || !providers.every((provider) => record(provider) && typeof provider.id === "string")) throw new Error("Invalid providers");
      const models = await Promise.all(providers.map(async (provider: { id: string }) => {
        const body = await get(`${base}/providers/${encodeURIComponent(provider.id)}/models${query}`, signal);
        return [provider.id, body.models];
      }));
      return [capability, Object.fromEntries(models)];
    }));
    return parseModelCatalog(Object.fromEntries(entries));
  }
  async function lookups(signal: AbortSignal): Promise<EditorLookups> {
    const value = await get(`${base}/call-spec-editor-lookups`, signal);
    if (!record(value.credential_names) || !Object.values(value.credential_names).every(names) || !names(value.mcp_integrations) ||
      !Array.isArray(value.telephony_services) || !value.telephony_services.every((service) => record(service) && typeof service.key === "string" && typeof service.name === "string")) throw new Error("Invalid editor lookups");
    return { credentialNames: value.credential_names as Record<string, string[]>, telephonyServices: value.telephony_services, mcpIntegrations: value.mcp_integrations };
  }
  async function phoneNumbers(service: string, search: string, page: string | null, signal: AbortSignal, callSpecId?: string): Promise<PhoneNumberPage> {
    const query = new URLSearchParams({ search });
    if (page) query.set("page", page);
    if (callSpecId) query.set("call_spec_id", callSpecId);
    const value = await get(`${base}/telephony-services/${encodeURIComponent(service)}/numbers?${query}`, signal);
    if (!Array.isArray(value.numbers) || value.numbers.length > 50 || !value.numbers.every((item) => record(item) && typeof item.id === "string" && typeof item.number === "string" && typeof item.name === "string" && typeof item.available === "boolean" && names(item.assigned_to)) || !(value.next_page === null || typeof value.next_page === "string")) throw new Error("Invalid phone number inventory");
    return { numbers: value.numbers.map((item) => ({ id: item.id, number: item.number, name: item.name, available: item.available, assignedTo: item.assigned_to })), nextPage: value.next_page };
  }
  return { read, execute, catalog, lookups, phoneNumbers };
}
