import { useState } from "react";
import { Link, useNavigate } from "react-router";
import { Button } from "../Button";
import { canCreateTenants } from "../authentication/access";
import { useConsoleNavigation } from "./navigationContext";

export function TenantCreationForm({ onCreate, onCancel }: { onCreate: (name: string) => Promise<void>; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);
  return <main><div className="navigation-heading"><div><h1>New tenant</h1></div></div>
    <form className="setup-create-form max-w-lg" onSubmit={async event => {
      event.preventDefault();
      if (busy || !name.trim()) return;
      setBusy(true); setError(false);
      try { await onCreate(name.trim()); } catch { setError(true); } finally { setBusy(false); }
    }}>
      <label>Give your tenant a name<input autoComplete="off" required maxLength={256} disabled={busy} value={name} onChange={event => setName(event.target.value)} /></label>
      {error ? <p role="alert" className="setup-error">Could not create the tenant. Please try again.</p> : null}
      <div className="setup-create-actions"><Button type="button" variant="ghost" disabled={busy} onClick={onCancel}>Cancel</Button><Button type="submit" disabled={busy || !name.trim()}>{busy ? "Creating…" : "Create tenant"}</Button></div>
    </form>
  </main>;
}
export function TenantCreationPage() {
  const { api, session, sessionUnavailable, data, fail } = useConsoleNavigation();
  const navigate = useNavigate();
  if (!session && !sessionUnavailable) return <main><p role="status">Loading permissions…</p></main>;
  if (!session || !canCreateTenants(session.role)) return <main><h1>Access unavailable</h1><p>Your role does not allow tenant creation.</p><Link to={data.directoryPath}>Back to tenants</Link></main>;
  return <TenantCreationForm onCancel={() => void navigate(data.directoryPath)} onCreate={async name => {
    try { const key = await api.createTenant(name); await navigate(`/t/${key}/dashboard`); }
    catch (error) { fail(error); throw error; }
  }} />;
}
