import { useEffect, useState } from "react";
import { Check, ChevronRight, Copy, Plus, Search } from "lucide-react";
import { Button } from "../Button";
import { Pagination } from "../Pagination";
import { DirectorySkeleton } from "../navigation/TenantDirectoryView";
import { formatAdminRelativeTime } from "../formatAdminRelativeTime";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../components/ui/tooltip";
import { ApiKeyTenantPicker } from "./ApiKeyTenantPicker";
import { keyLabels, type AccessKey, type AccessKeysClient, type KeyKind, type KeyPage, type KeyTenant } from "./accessKeysApi";

export function ApiKeysPage({ api, initialCreating = false, initialKind = "calls", authority, onCreatingChange }: {
  api: AccessKeysClient; authority?: unknown; initialCreating?: boolean; initialKind?: KeyKind; onCreatingChange?: (value: boolean) => void;
}) {
  const [creating, setCreating] = useState(initialCreating);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [revision, setRevision] = useState(0);
  const [result, setResult] = useState<KeyPage>();
  const [failed, setFailed] = useState(false);
  const [name, setName] = useState("Application");
  const [kind, setKind] = useState<KeyKind>(initialKind);
  const [tenant, setTenant] = useState<KeyTenant | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [reveal, setReveal] = useState<{ key: AccessKey; secret: string }>();
  const [confirm, setConfirm] = useState<string>();
  useEffect(() => { setReveal(undefined); setTenant(null); }, [authority]);
  useEffect(() => {
    const controller = new AbortController();
    setResult(undefined); setFailed(false);
    const timer = setTimeout(() => api.list(query, page, controller.signal).then(data => {
      if (!controller.signal.aborted) setResult(data);
    }).catch(() => { if (!controller.signal.aborted) setFailed(true); }), query ? 200 : 0);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [api, query, page, revision, authority]);
  const effectiveKind = result?.kinds.includes(kind) ? kind : result?.kinds[0];
  const showForm = creating && !reveal && !!result?.kinds.length;
  function changeCreating(value: boolean) {
    setCreating(value); setError(undefined); setTenant(null); setReveal(undefined);
    onCreatingChange?.(value);
  }
  async function create(event: React.FormEvent) {
    event.preventDefault();
    if (!effectiveKind || busy || !name.trim() || (effectiveKind !== "platform" && !tenant)) return;
    setBusy(true); setError(undefined);
    try {
      const issued = await api.create(name.trim(), effectiveKind, effectiveKind === "platform" ? null : tenant!.key);
      setReveal(issued); setRevision(value => value + 1);
    } catch { setError("The API key could not be created. Please try again."); }
    finally { setBusy(false); }
  }
  async function revoke(id: string) {
    setBusy(true); setError(undefined);
    try { await api.revoke(id); setConfirm(undefined); setRevision(value => value + 1); }
    catch { setError("The API key could not be revoked. Please try again."); }
    finally { setBusy(false); }
  }
  return <main className="tenant-setup">
    {showForm ? <nav aria-label="Breadcrumb" className="navigation-context"><button disabled={busy} onClick={() => changeCreating(false)}>API Keys</button><ChevronRight size={14} aria-hidden /><span aria-current="page">New API Key</span></nav> : null}
    <header className="setup-section-heading"><h1>{showForm ? "New API Key" : "API Keys"}</h1>
      {!creating && !reveal && !!result?.kinds.length ? <Button onClick={() => changeCreating(true)}><Plus size={16} aria-hidden />Create API key</Button> : null}
    </header>
    {error ? <p role="alert" className="setup-error">{error}</p> : null}
    {reveal ? <KeyReveal value={reveal} onDone={() => changeCreating(false)} /> : null}
    {failed ? <p role="alert">API keys could not be loaded.</p> : !result ? <DirectorySkeleton label="Loading API keys" /> : showForm ? <form onSubmit={event => void create(event)} className="max-w-xl space-y-5">
      <label className="grid gap-2 text-sm sm:grid-cols-[110px_minmax(0,1fr)] sm:items-center"><span>Name</span><input value={name} onChange={event => setName(event.target.value)} disabled={busy} required maxLength={256} className="h-10 min-w-0 rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] px-3" /></label>
      <label className="grid gap-2 text-sm sm:grid-cols-[110px_minmax(0,1fr)] sm:items-center"><span>Access type</span><select value={effectiveKind} disabled={busy} onChange={event => { setKind(event.target.value as KeyKind); setTenant(null); }} className="h-10 min-w-0 rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] pl-3 pr-9">
        {result.kinds.map(item => <option key={item} value={item}>{keyLabels[item]}</option>)}
      </select></label>
      {effectiveKind !== "platform" ? <div className="grid gap-2 text-sm sm:grid-cols-[110px_minmax(0,1fr)] sm:items-center"><span>Tenant</span><ApiKeyTenantPicker api={api} kind={effectiveKind!} selected={tenant} onSelect={setTenant} disabled={busy} /></div> : <p className="text-sm text-[var(--admin-muted)]">Access to the platform and all tenants.</p>}
      <div className="flex justify-end gap-2"><Button type="button" disabled={busy} onClick={() => changeCreating(false)}>Cancel</Button><Button className="setup-primary" type="submit" disabled={busy || !name.trim() || (effectiveKind !== "platform" && !tenant)}>{busy ? "Creating…" : "Create API key"}</Button></div>
    </form> : !reveal ? <>
      {creating && !result.kinds.length ? <p className="mb-5 text-sm text-[var(--admin-muted)]">Your permissions do not allow creating API keys.</p> : null}
      <label className="navigation-filter mb-6"><Search size={16} aria-hidden /><input aria-label="Search API keys" placeholder="Search keys or tenants" value={query} onChange={event => { setQuery(event.target.value); setPage(1); }} maxLength={120} /></label>
      {result.keys.length ? <div className="setup-api-key-table-wrap"><table aria-label="API keys" className="setup-api-key-table">
        <thead><tr><th scope="col">Name</th><th scope="col">API key</th><th scope="col">Type</th><th scope="col">Tenant</th><th scope="col">Created</th><th scope="col"><span className="sr-only">Actions</span></th></tr></thead>
        <tbody>{result.keys.map(item => <tr key={item.id}><td>{item.name}</td><td><code>{item.lastFour ? "••••••••" + item.lastFour : "—"}</code></td><td>{keyLabels[item.kind]}</td><td>{item.tenant?.name ?? "All tenants"}</td><td><CreatedTime value={item.createdAt} /></td><td>
          {item.canRevoke ? confirm === item.id ? <div className="flex gap-2"><Button disabled={busy} onClick={() => void revoke(item.id)}>Confirm revoke</Button><Button disabled={busy} onClick={() => setConfirm(undefined)}>Cancel</Button></div> : <Button disabled={busy} aria-label={`Revoke ${item.name}`} onClick={() => setConfirm(item.id)}>Revoke</Button> : null}
        </td></tr>)}</tbody>
      </table></div> : <p className="text-sm text-[var(--admin-muted)]">{query ? "No API keys match your search." : "No API keys yet."}</p>}
      {page > 1 || result.hasNext ? <Pagination ariaLabel="API key pages" pagination={{ label: `Page ${page}`, hasPrevious: page > 1, hasNext: result.hasNext }} onPrevious={() => setPage(p => p - 1)} onNext={() => setPage(p => p + 1)} /> : null}
    </> : null}
  </main>;
}
function KeyReveal({ value, onDone }: { value: { key: AccessKey; secret: string }; onDone: () => void }) {
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  return <section className="setup-key-created max-w-xl" aria-label="API key created"><h2><Check size={18} aria-hidden />API key created</h2><strong>{value.key.name}</strong>
    <p>Copy this key now. It will not be shown again.</p>
    <label className="setup-key-name">API key<input readOnly value={value.secret} onFocus={event => event.target.select()} /></label>
    <div className="flex gap-2"><Button onClick={() => { void navigator.clipboard.writeText(value.secret).then(() => { setCopied(true); setFailed(false); }).catch(() => setFailed(true)); }}><Copy size={15} aria-hidden />{copied ? "Copied" : "Copy API key"}</Button><Button onClick={onDone}>Done</Button></div>
    {failed ? <p role="alert">Copy failed. Select and copy the key manually.</p> : null}
  </section>;
}
function CreatedTime({ value }: { value: string }) {
  const relative = formatAdminRelativeTime(value);
  return <TooltipProvider><Tooltip><TooltipTrigger asChild><time tabIndex={0} dateTime={value}>{relative === "just now" ? "few seconds ago" : relative}</time></TooltipTrigger><TooltipContent className="setup-service-tooltip">{new Date(value).toUTCString().replace("GMT", "UTC")}</TooltipContent></Tooltip></TooltipProvider>;
}
