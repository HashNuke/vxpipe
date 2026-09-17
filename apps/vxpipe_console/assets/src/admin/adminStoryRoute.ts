export type AdminStoryRoute =
  | { page: "tenants" }
  | { page: "definitions"; tenantKey: string }
  | { page: "calls"; tenantKey: string; definitionId?: string }
  | { page: "services"; tenantKey: string }
  | { page: "call-details"; tenantKey: string; callId: string };

export function adminStoryPath(route: AdminStoryRoute) {
  switch (route.page) {
    case "tenants":
      return "/admin";
    case "definitions":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/definitions`;
    case "calls":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/calls${route.definitionId ? `?definition_id=${encodeURIComponent(route.definitionId)}` : ""}`;
    case "services":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/services`;
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

  const callsMatch = hash.match(
    /^#\/admin\/tenants\/([^/]+)\/calls(?:\?definition_id=([^&]+))?$/,
  );
  if (callsMatch) {
    try {
      return {
        page: "calls",
        tenantKey: decodeURIComponent(callsMatch[1]),
        ...(callsMatch[2]
          ? { definitionId: decodeURIComponent(callsMatch[2]) }
          : {}),
      };
    } catch {
      return { page: "tenants" };
    }
  }

  const servicesMatch = hash.match(/^#\/admin\/tenants\/([^/]+)\/services$/);
  if (servicesMatch) {
    try {
      return {
        page: "services",
        tenantKey: decodeURIComponent(servicesMatch[1]),
      };
    } catch {
      return { page: "tenants" };
    }
  }

  const match = hash.match(/^#\/admin\/tenants\/([^/]+)(?:\/definitions)?$/);
  if (!match) return { page: "tenants" };

  try {
    return { page: "definitions", tenantKey: decodeURIComponent(match[1]) };
  } catch {
    return { page: "tenants" };
  }
}
