import type { CallDetailsPageState } from "../callDetailsTypes";
import { adminStoryHref } from "../adminStoryHref";
import { StoryPageBreadcrumbs } from "./StoryPageBreadcrumbs";

export function StoryCallBreadcrumbs({ state, theme }: { state: CallDetailsPageState; theme: "dark" | "light" }) {
  const base = `/admin/tenants/${encodeURIComponent(state.tenant.key)}`;
  return <div className="story-call-breadcrumbs"><StoryPageBreadcrumbs tenant
    root={{ label: state.tenant.name ?? state.tenant.key, href: adminStoryHref(`${base}/call-specs`, theme) }}
    items={[
      { label: "Calls", href: adminStoryHref(`${base}/calls`, theme) },
      ...(state.callSpec ? [{ label: state.callSpec.name ?? state.callSpec.id, href: adminStoryHref(`${base}/calls?call_spec_id=${encodeURIComponent(state.callSpec.id)}`, theme) }] : []),
      { label: "Call details" },
    ]} /></div>;
}
