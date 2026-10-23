export type CallSpecOption = { id: string; name: string | null };
export type CallSpecSearch = (
  query: string,
  page: number,
  signal: AbortSignal,
) => Promise<{ options: CallSpecOption[]; hasMore: boolean }>;

export function callSpecSearch(
  fetchImpl: typeof fetch,
  tenantKey: string,
  onSessionExpired: () => void,
): CallSpecSearch {
  return async (query, page, signal) => {
    const params = new URLSearchParams({ q: query, page: String(page) });
    const response = await fetchImpl(
      `/api/tenants/${encodeURIComponent(tenantKey)}/calls/spec-options?${params}`,
      { signal, headers: { accept: "application/json" } },
    );
    if (response.status === 401) onSessionExpired();
    if (!response.ok) throw new Error("Call specs could not be loaded.");
    const result = await response.json();
    if (
      !Array.isArray(result.options) ||
      typeof result.has_more !== "boolean" ||
      !result.options.every((option: CallSpecOption) =>
        option && typeof option.id === "string" && option.id.length > 0 &&
        (option.name === null || typeof option.name === "string"),
      )
    ) throw new Error("Invalid call spec search response.");
    return { options: result.options, hasMore: result.has_more };
  };
}
