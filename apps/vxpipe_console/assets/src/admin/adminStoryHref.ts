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
    id: "vxpipe-console-full-journey--review-flow",
    viewMode: "story",
    args: `theme:${theme}`,
  });
  return `./iframe.html?${query}#${path}`;
}
