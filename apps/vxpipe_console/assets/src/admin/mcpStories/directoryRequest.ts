/** Storybook build reads the same VERSION file as the OTP applications. */
export const installationVersion = import.meta.env.STORYBOOK_VXPIPE_VERSION;
export type DirectoryRequest = {
  resource: "categories" | "integrations";
  category: string | null;
  query: string;
  cursor: string | null;
  limit: number;
  scope: "tenant" | "platform";
  headers: Record<string, string>;
  path: string;
};
/** Declarative request only; this prototype does not fetch the remote service. */
export function directoryRequest({ resource = "integrations", category = null, query = "", cursor = null, limit = 20, scope = "tenant", version = installationVersion }: {
  resource?: DirectoryRequest["resource"]; category?: string | null; query?: string;
  cursor?: string | null; limit?: number; scope?: DirectoryRequest["scope"]; version?: string;
}): DirectoryRequest {
  const q = query.trim();
  const filteredCategory = q ? null : category;
  const params = new URLSearchParams({ limit: String(limit), scope });
  if (q) params.set("q", q);
  else if (filteredCategory) params.set("category", filteredCategory);
  if (cursor) params.set("cursor", cursor);
  return { resource, category: filteredCategory, query: q, cursor, limit, scope,
    headers: { Accept: "application/json", "X-VxPipe-Version": version }, path: `/v1/${resource}?${params}` };
}
