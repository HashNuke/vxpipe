export type AdminStoryRoute =
  | { page: "tenants" }
  | { page: "definitions"; tenantKey: string }
  | { page: "calls"; tenantKey: string; definitionId: string }
  | { page: "call-details"; tenantKey: string; callId: string };

export function adminStoryPath(route: AdminStoryRoute) {
  switch (route.page) {
    case "tenants":
      return "/admin";
    case "definitions":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}`;
    case "calls":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/definitions/${encodeURIComponent(route.definitionId)}`;
    case "call-details":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/calls/${encodeURIComponent(route.callId)}`;
  }
}

export function adminStoryRoute(hash: string): AdminStoryRoute {
  const callMatch = hash.match(/^#\/admin\/tenants\/([^/]+)\/calls\/([^/]+)$/);
  if (callMatch) {
    try {
      return {
        page: "call-details",
        tenantKey: decodeURIComponent(callMatch[1]),
        callId: decodeURIComponent(callMatch[2]),
      };
    } catch {
      return { page: "tenants" };
    }
  }

  const definitionMatch = hash.match(
    /^#\/admin\/tenants\/([^/]+)\/definitions\/([^/]+)$/,
  );
  if (definitionMatch) {
    try {
      return {
        page: "calls",
        tenantKey: decodeURIComponent(definitionMatch[1]),
        definitionId: decodeURIComponent(definitionMatch[2]),
      };
    } catch {
      return { page: "tenants" };
    }
  }

  const match = hash.match(/^#\/admin\/tenants\/([^/]+)$/);
  if (!match) return { page: "tenants" };

  try {
    return { page: "definitions", tenantKey: decodeURIComponent(match[1]) };
  } catch {
    return { page: "tenants" };
  }
}
