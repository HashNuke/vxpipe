import { useCallback, useEffect, useRef, useState } from "react";

export const integrationCategories: Record<string, string> = {
  connected: "Connected integrations", ai: "AI models", telephony: "Telephony", search: "Search results",
};
export type DirectoryCategory = string;
type DirectoryRoute = { category: string; search: string; cursor: string | null };
function routeHash(base: string, route: DirectoryRoute) {
  const query = new URLSearchParams();
  if (route.search) query.set("q", route.search);
  if (route.cursor) query.set("cursor", route.cursor);
  return `#${base}/${route.category}${query.size ? `?${query}` : ""}`;
}

/** Preview routes retain server cursors and filters without adding live endpoints. */
export function useIntegrationCategoryRoute(base: string, platform: boolean, initial: DirectoryCategory) {
  const fromLocation = useCallback((): DirectoryRoute | undefined => {
    const [path, params] = window.location.hash.slice(1).split("?");
    if (path === base) return { category: "connected", search: "", cursor: null };
    if (!path.startsWith(`${base}/`)) return undefined;
    const value = path.slice(base.length + 1);
    const category = /^[a-z][a-z0-9-]{0,63}$/.test(value) && (!platform || Object.hasOwn(integrationCategories, value)) ? value : "connected";
    const query = new URLSearchParams(params);
    const search = (query.get("q") ?? "").slice(0, 200);
    const resolvedCategory = search.trim() ? "search" : category;
    return { category: resolvedCategory, search, cursor: resolvedCategory === "connected" ? null : query.get("cursor") };
  }, [base, platform]);
  const [route, setRoute] = useState<DirectoryRoute>(() => fromLocation() ?? { category: initial, search: "", cursor: null });
  const returnCategory = useRef(route.category === "search" ? "connected" : route.category);
  useEffect(() => {
    const read = () => { const next = fromLocation(); if (next) setRoute(next); };
    for (const event of ["popstate", "hashchange", "storynavigate"]) window.addEventListener(event, read);
    return () => { for (const event of ["popstate", "hashchange", "storynavigate"]) window.removeEventListener(event, read); };
  }, [fromLocation]);
  useEffect(() => {
    const hash = routeHash(base, route);
    if (window.location.hash !== hash) window.history.replaceState({}, "", hash);
  }, [base, route]);
  function update(next: DirectoryRoute, replace = false) {
    const hash = routeHash(base, next);
    if (hash !== window.location.hash) window.history[replace ? "replaceState" : "pushState"]({}, "", hash);
    setRoute(next);
  }
  return {
    category: route.category, search: route.search, cursor: route.cursor,
    navigate: (category: DirectoryCategory) => { returnCategory.current = category; update({ category, search: "", cursor: null }); },
    setSearch: (search: string) => {
      if (route.category !== "search") returnCategory.current = route.category;
      update({ category: search.trim() ? "search" : returnCategory.current, search, cursor: null }, true);
    },
    setCursor: (cursor: string | null) => update({ ...route, cursor }),
    href: (category: DirectoryCategory) => routeHash(base, { category, search: "", cursor: null }),
  };
}
