export type AdminStoryRoute =
  | { page: "tenants" }
  | { page: "definitions"; tenantKey: string; definitionId?: string };

export function adminStoryPath(route: AdminStoryRoute) {
  switch (route.page) {
    case "tenants":
      return "/admin";
    case "definitions":
      return route.definitionId
        ? `/admin/tenants/${encodeURIComponent(route.tenantKey)}/definitions/${encodeURIComponent(route.definitionId)}`
        : `/admin/tenants/${encodeURIComponent(route.tenantKey)}`;
  }
}

export function adminStoryRoute(hash: string): AdminStoryRoute {
  const definitionMatch = hash.match(
    /^#\/admin\/tenants\/([^/]+)\/definitions\/([^/]+)$/,
  );
  if (definitionMatch) {
    try {
      return {
        page: "definitions",
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
