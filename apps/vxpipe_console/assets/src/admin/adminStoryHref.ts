import { adminStoryPath } from "./adminStoryRoute";

export function callDetailsStoryHref(
  tenantKey: string,
  callId: string,
  theme: "dark" | "light",
) {
  return adminStoryHref(adminStoryPath({ page: "call-details", tenantKey, callId }), theme);
}

export function adminStoryHref(path: string, theme: "dark" | "light") {
  const query = new URLSearchParams({
    id: /\/calls\/[^/]+$/.test(path) ? "vxpipe-console-calls-history--ongoing"
      : /\/calls(?:\?|$)/.test(path) ? "vxpipe-console-calls-calls--populated"
        : path.endsWith("/call-specs") ? "vxpipe-console-call-specs-call-specs--populated"
          : path.endsWith("/services") ? "vxpipe-console-services-tenant-inventory--populated"
            : "vxpipe-console-tenants-directory--populated",
    viewMode: "story",
    args: `theme:${theme}`,
  });
  return `./iframe.html?${query}#${path}`;
}
