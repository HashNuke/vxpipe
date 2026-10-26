import { createContext } from "react";

export type StoryCrumb = { label: string; href?: string; onSelect?: () => void };
export type StoryNavigation = {
  root: StoryCrumb;
  tenant: boolean;
  navigate: (path: string) => void;
};
/** Opt-in presentation context. Live pages retain their current navigation. */
export const StoryNavigationContext = createContext<StoryNavigation | null>(null);

export function storyNavigation(path: string, navigate: StoryNavigation["navigate"], tenant?: { key: string; name: string }): StoryNavigation {
  return {
    root: tenant && path.startsWith("/t/")
      ? { label: tenant.name, href: `/t/${tenant.key}/dashboard` }
      : { label: path.startsWith("/tenants") ? "Tenants" : "Settings" },
    tenant: Boolean(tenant && path.startsWith("/t/")),
    navigate,
  };
}

export function storyPathCrumbs(path: string): StoryCrumb[] {
  const parts = path.split("/").filter(Boolean);
  const leaf = parts[0] === "t" ? parts[2] : parts[0] === "platform" ? parts[1] : parts[0];
  const names: Record<string, string> = { dashboard: "Dashboard", calls: "Calls", "call-specs": "Call Specs", services: "Services", "legacy-services": "Services", samples: "Call specs", "api-keys": "API Keys", roles: "Roles", users: "Users", installation: "Installation", account: "My account", diagnostics: "Diagnostics", "getting-started": "Getting started" };
  if (leaf === "tenants") return parts[1] === "new" ? [{ label: "Create tenant" }] : [];
  if (leaf === "roles" || leaf === "users") {
    if (!parts[1]) return [{ label: names[leaf] }];
    return [{ label: names[leaf], href: `/${leaf}` },
      { label: parts[1] === "new" ? `Create ${leaf === "roles" ? "role" : "user"}` : `${leaf === "roles" ? "Role" : "User"} details`, ...(parts[2] ? { href: `/${leaf}/${parts[1]}` } : {}) },
      ...(parts[2] ? [{ label: "Reset password" }] : [])];
  }
  return names[leaf] ? [{ label: names[leaf] }] : [];
}
