export type AdminStoryRoute =
  | { page: "tenants" }
  | { page: "call-specs"; tenantKey: string }
  | { page: "calls"; tenantKey: string; callSpecId?: string }
  | { page: "services"; tenantKey: string }
  | { page: "call-details"; tenantKey: string; callId: string };

export function adminStoryPath(route: AdminStoryRoute) {
  switch (route.page) {
    case "tenants":
      return "/admin";
    case "call-specs":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/call-specs`;
    case "calls":
      return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/calls${route.callSpecId ? `?call_spec_id=${encodeURIComponent(route.callSpecId)}` : ""}`;
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
    /^#\/admin\/tenants\/([^/]+)\/calls(?:\?call_spec_id=([^&]+))?$/,
  );
  if (callsMatch) {
    try {
      return {
        page: "calls",
        tenantKey: decodeURIComponent(callsMatch[1]),
        ...(callsMatch[2]
          ? { callSpecId: decodeURIComponent(callsMatch[2]) }
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

  const match = hash.match(/^#\/admin\/tenants\/([^/]+)(?:\/call-specs)?$/);
  if (!match) return { page: "tenants" };

  try {
    return { page: "call-specs", tenantKey: decodeURIComponent(match[1]) };
  } catch {
    return { page: "tenants" };
  }
}
