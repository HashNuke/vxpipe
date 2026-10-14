import { useEffect, useState, type ReactNode } from "react";
import { Building2 } from "lucide-react";
import { AuthenticationJourney } from "../authentication/AuthenticationJourney";
import { AccountPage } from "../authentication/AccountPage";
import { AuthPage } from "../authentication/AuthPage";
import { tenants } from "../authentication/fixtures";
import type { Theme, Tenant, Role, User } from "../authentication/types";
import { AdminShell } from "../AdminShell";
import { DirectorySkeleton, TenantDirectoryView } from "./TenantDirectoryView";
import { Pagination } from "../Pagination";
import { TenantCreationForm } from "./TenantCreationPage";
import { canCreateTenants } from "../authentication/access";
import { Button } from "../Button";
import { CallList } from "../CallList";
import { CallSpecList } from "../CallSpecList";
import { CallSpecCombobox } from "../CallSpecCombobox";
import { callsForTenant } from "../callFixtures";
import { callSpecs } from "../callSpecFixtures";
import { CallDetailsStory } from "../CallDetailsStory";
import { NavigationAuxiliary } from "./NavigationAuxiliary";
import { RecentCalls } from "./RecentCalls";
import { navigationFixture, type Persona } from "./navigationFixtures";
import { NavigationShell } from "./NavigationShell";
import { NavigationEditor } from "./NavigationEditor";
import { NavigationServices } from "./NavigationServices";
import { landingPath, navigationItems, tenantAccess, visibleTenants } from "./navigationPolicy";
import "./navigation.css";

export type NavigationState = "ready" | "loading" | "unavailable" | "empty";
export function NavigationJourney({ persona = "all", initialPath = "/", theme = "dark", state = "ready", pickerState = "ready", initialTenants = tenants, directoryPageSize = 25, creationOutcome = "ready", identity }: {
  creationOutcome?: "ready" | "error" | "pending"; directoryPageSize?: number; identity?: { role: Role; user: User }; initialTenants?: Tenant[]; persona?: Persona; initialPath?: string; theme?: Theme; state?: NavigationState; pickerState?: "ready" | "loading" | "unavailable";
}) {
  const [directoryTenants, setDirectoryTenants] = useState(initialTenants);
  const { user, role } = identity ?? navigationFixture(persona);
  const visible = visibleTenants(role, user, directoryTenants);
  const landing = landingPath(role, user, directoryTenants);
  const [path, setPath] = useState(initialPath === "/" ? landing : initialPath.split("?")[0]);
  const [selection, setSelection] = useState<string>();
  const [signedOut, setSignedOut] = useState(false);
  const [query, setQuery] = useState("");
  const [directoryPage, setDirectoryPage] = useState(1);
  const [filter, setFilter] = useState<string | null>(new URLSearchParams(initialPath.split("?")[1]).get("call_spec_id"));
  const [phase] = useState(state);
  const [pickerPhase, setPickerPhase] = useState(pickerState);
  const key = path.startsWith("/t/") ? decodeURIComponent(path.split("/")[2]) : selection;
  const tenant = visible.find(item => item.key === key);
  useEffect(() => {
    const listener = () => { const next = window.location.hash.slice(1); if (next.startsWith("/") && !next.startsWith("/admin")) setPath(next === "/" ? landing : next); };
    window.addEventListener("popstate", listener);
    return () => window.removeEventListener("popstate", listener);
  }, [landing]);
  function navigate(next: string) {
    if (tenant) setSelection(tenant.key);
    const resolved = next === "/" ? landing : next;
    setPath(resolved.split("?")[0]); setQuery(""); setFilter(new URLSearchParams(resolved.split("?")[1]).get("call_spec_id"));
    window.history.pushState({}, "", `#${resolved}`);
    window.scrollTo({ top: 0, behavior: "instant" });
  }
  const link = (href: string, label: ReactNode, className?: string) => <a className={className} href={`#${href}`} onClick={event => { event.preventDefault(); navigate(href); }}>{label}</a>;
  const shell = (content: ReactNode, activePath = path) => <NavigationShell role={role} user={user} tenants={visible} selected={tenant} path={activePath} onNavigate={navigate} onLogout={() => { setSignedOut(true); setSelection(undefined); }} theme={theme} pickerState={pickerPhase} onRetry={() => setPickerPhase("ready")}>{content}</NavigationShell>;
  const heading = (title: string, description?: string, action?: ReactNode) => <div className="navigation-heading"><div><h1>{title}</h1>{description ? <p>{description}</p> : null}</div>{action}</div>;
  const context = tenant ? <div className="navigation-context"><Building2 size={15} aria-hidden />{link(`/t/${tenant.key}/dashboard`, <span aria-label={`${tenant.name} dashboard`}>{tenant.name}</span>)}</div> : null;
  const empty = (title: string, detail: string) => <div className="navigation-empty"><h2>{title}</h2><p>{detail}</p></div>;
  if (signedOut || path.startsWith("/auth/")) return <AdminShell theme={theme} showHeader={false}><div className="access-ui"><AuthPage mode={path === "/auth/setup" ? "setup" : path === "/auth/recover" ? "recover" : "login"} onSubmit={async () => { setSignedOut(false); navigate("/"); return {}; }} /></div></AdminShell>;
  if (/^\/(users|roles)(\/|$)/.test(path)) return <AuthenticationJourney key={`${persona}-${path}`} actor={role.kind === "superadmin" ? "superadmin" : role.kind === "admin" ? "admin" : "member"} initialPath={path} theme={theme} followLocation={false} renderFrame={(content, authPath) => shell(content, authPath.replace(/^\/admin/, ""))} />;
  if (path === "/account") return shell(<div className="access-ui"><AccountPage user={user} role={role} onSave={async () => ({})} /></div>);
  if (path.endsWith("/editor") && tenant && tenantAccess(role, user, tenant, "call_specs") !== "none") return <NavigationEditor readOnly={tenantAccess(role, user, tenant, "call_specs") !== "write"} theme={theme} backPath={`/t/${tenant.key}/call-specs`} onNavigate={navigate} />;
  if (/\/calls\/[^/]+$/.test(path)) return <CallDetailsStory scenario={tenant && tenantAccess(role, user, tenant, "calls") !== "none" ? "ended" : "unavailable"} theme={theme} />;
  if (path === "/platform/services" && !navigationItems(role, user).platform.some(item => item.href === path)) return shell(<main>{heading("Access unavailable")}{empty("Permission required", "Your role does not allow this action.")}</main>);
  if (path === "/platform/services") return shell(<NavigationServices tenant={tenants[0]} platform readOnly={!role.kind && !role.grants.some(grant => grant.permission === "platform_services.write" && grant.scope === "installation")} onNavigate={navigate} />);
  if (["/getting-started", "/samples/voice", "/samples/transfer"].includes(path) && !canCreateTenants(role)) return shell(<main>{heading("Access unavailable")}{empty("Permission required", "Your role does not allow platform sample setup.")}</main>);
  if (path === "/diagnostics" && !role.kind && !role.grants.some(grant => grant.permission === "diagnostics.read")) return shell(<main>{heading("Access unavailable")}{empty("Permission required", "Your role does not allow diagnostics.")}</main>);
  if (["/diagnostics", "/samples/voice", "/samples/transfer"].includes(path)) return shell(<main>{heading(path === "/diagnostics" ? "Diagnostics" : path === "/samples/voice" ? "Voice console" : "Human transfer desk")}
    {path === "/diagnostics" ? <>{empty("Reporter offline", "The bounded diagnostics collector could not be reached. Call traffic is unaffected; check the Console supervision tree, then reload this page.")}<div className="navigation-shortcuts">{link("/samples/voice", "Voice console")}</div></>
    : <>{empty("Disconnected", path === "/samples/transfer" ? "In the caller console, ask the agent for human support. Then connect this desk to hear the private briefing before you accept." : "Choose a call spec and configure its services before starting a voice call.")}<div className="navigation-shortcuts">{link("/getting-started", "Prepare a sample call")}{link(path === "/samples/voice" ? "/samples/transfer" : "/samples/voice", path === "/samples/voice" ? "Human transfer desk" : "Voice console")}</div></>}
  </main>);
  if (path === "/getting-started") return shell(<NavigationAuxiliary page="getting-started" tenant={tenant ?? tenants[0]} onNavigate={navigate} />);
  if (path === "/tenants/new") return shell(canCreateTenants(role) ? <TenantCreationForm onCancel={() => navigate("/tenants")} onCreate={async name => {
    if (creationOutcome === "error") throw new Error("Storybook creation unavailable");
    if (creationOutcome === "pending") await new Promise<void>(() => {});
    const next = { id: `example-${directoryTenants.length}`, key: `example_tenant_${directoryTenants.length}`, createdAt: new Date().toISOString(), name };
    setDirectoryTenants(current => [...current, next]); navigate(`/t/${next.key}/dashboard`);
  }} /> : <main>{heading("Access unavailable")}{empty("Permission required", "Your role does not allow tenant creation.")}</main>);
  if (path === "/tenants" || path === "/my-tenants") {
    const title = path === "/tenants" ? "Tenants" : "My tenants";
    const matching = visible.filter(item => `${item.name} ${item.key}`.toLowerCase().includes(query.toLowerCase()));
    const count = matching.length;
    const pages = Math.ceil(count / directoryPageSize);
    return shell(<TenantDirectoryView title={title} state={phase === "empty" ? "ready" : phase}
      tenants={phase === "empty" ? [] : matching.slice((directoryPage - 1) * directoryPageSize, directoryPage * directoryPageSize).map(item => ({ ...item, canSetup: tenantAccess(role, user, item, "tenant_services") === "write" }))}
      query={query} onQueryChange={value => { setQuery(value); setDirectoryPage(1); }} canCreate={canCreateTenants(role)}
      link={(href, children, label) => <a href={`#${href}`} aria-label={label} onClick={event => { event.preventDefault(); navigate(href); }}>{children}</a>}
      pagination={pages > 1 ? <Pagination ariaLabel="Tenant pages" pagination={{ label: `Page ${directoryPage} of ${pages}`, hasPrevious: directoryPage > 1, hasNext: directoryPage < pages }} onPrevious={() => setDirectoryPage(value => value - 1)} onNext={() => setDirectoryPage(value => value + 1)} /> : null}
    />);
  }
  if (!tenant) return shell(<main>{heading("Workspace unavailable")}{empty("Tenant access unavailable", "This tenant may no longer be available to you. Choose another tenant to continue.")}</main>);
  const leaf = path.split("/")[3];
  const nav = navigationItems(role, user, tenant).tenant;
  const canCalls = tenantAccess(role, user, tenant, "calls") !== "none";
  const list = callsForTenant().filter(call => !filter || call.callSpecId === filter);
  const callHref = (id: string) => `?id=vxpipe-console-calls-history--ended&viewMode=story#/t/${tenant.key}/calls/${id}`;
  const calls = leaf === "dashboard" ? <RecentCalls calls={list.slice(0, 5)} callHref={callHref} /> : <CallList calls={list} tenant={tenant} callHref={callHref} />;
  if (leaf !== "dashboard" && !["api-keys", "samples", "legacy-services"].includes(leaf) && !nav.some(item => item.href === path)) return shell(<main>{context}{heading("Access unavailable")}{empty("Permission required", "Your role does not allow this action for this tenant.")}</main>);
  if (leaf === "services") return shell(<main>{context}<NavigationServices key={tenant.key} tenant={tenant} canReadKeys={tenantAccess(role, user, tenant, "tenant_api_keys") !== "none"} readOnly={tenantAccess(role, user, tenant, "tenant_api_keys") !== "write"} onNavigate={navigate} /></main>);
  if ((leaf === "legacy-services" && tenantAccess(role, user, tenant, "tenant_services") === "none") || (leaf === "api-keys" && tenantAccess(role, user, tenant, "tenant_api_keys") === "none") || (leaf === "samples" && (!canCreateTenants(role) || tenantAccess(role, user, tenant, "call_specs") !== "write"))) return shell(<main>{heading("Access unavailable")}{empty("Permission required", "Your role does not allow this action.")}</main>);
  if (["api-keys", "samples", "legacy-services"].includes(leaf)) return shell(<>{context}<NavigationAuxiliary canReadKeys={tenantAccess(role, user, tenant, "tenant_api_keys") !== "none"} readOnly={tenantAccess(role, user, tenant, "tenant_api_keys") !== "write"} key={`${tenant.key}-${leaf}`} page={leaf} tenant={tenant} onNavigate={navigate} /></>);
  const title = leaf === "dashboard" ? "Dashboard" : leaf === "calls" ? "Calls" : "Call Specs";
  return shell(<main>{context}{heading(title, undefined,
    leaf === "call-specs" && tenantAccess(role, user, tenant, "call_specs") === "write" ? <Button onClick={() => window.open("?id=vxpipe-console-call-spec-editor-page--new-spec&viewMode=story", "_blank", "noopener")}>New call spec</Button> : undefined)}
    {leaf === "calls" ? <div className="mb-6 max-w-80"><label className="mb-2 block text-xs" id="navigation-call-filter">Call spec</label><CallSpecCombobox options={callSpecs} selectedId={filter} unknownSelection={false} onSelect={setFilter} /></div> : null}
    {leaf === "dashboard" && canCalls ? <div className="navigation-section-title"><h2>Recent calls</h2>{link(`/t/${tenant.key}/calls`, "View all calls")}</div> : null}
    {phase === "loading" ? <DirectorySkeleton label={leaf === "dashboard" ? "Loading dashboard" : leaf === "call-specs" ? "Loading call specs" : "Loading calls"} /> : phase === "unavailable" ? <div role="alert">{empty("Activity unavailable", "We could not load this workspace.")}</div> : phase === "empty" ? empty("No activity yet", "Once this tenant has activity, it will appear here.") : leaf === "call-specs" ? <CallSpecList callSpecs={callSpecs} tenant={tenant} onSelectCallSpec={id => { navigate(`/t/${tenant.key}/calls`); setFilter(id); }} onEditCallSpec={() => navigate(`/t/${tenant.key}/editor`)} /> : canCalls ? calls : null}
  </main>);
}
