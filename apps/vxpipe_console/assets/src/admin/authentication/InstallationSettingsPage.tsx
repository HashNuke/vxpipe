import { useState, type FormEvent } from "react";
import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";
import { FormField, FormMessage } from "./FormField";
import { normalizeInstanceUrl } from "./instanceUrl";
import type { PageState, SaveResult, SystemKind } from "./types";

/** Shared presentation for persisted settings and interactive Storybook fixtures. */
export function InstallationSettingsPage({ roleKind, publicUrl, onSave, state = "ready", onRetry }: {
  roleKind: SystemKind; publicUrl: string; onSave: (url: string) => Promise<SaveResult>;
  state?: PageState; onRetry?: () => void;
}) {
  const [savedUrl, setSavedUrl] = useState(publicUrl);
  const [draft, setDraft] = useState(publicUrl);
  const [proposedUrl, setProposedUrl] = useState<string>();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();

  if (roleKind !== "superadmin") return <main className="access-page">
    <h1>Access unavailable</h1>
    <p className="access-lead">Only Superadmins can manage installation settings.</p>
  </main>;

  async function save(url: string) {
    setPending(true); setError(undefined); setNotice(undefined);
    try {
      const result = await onSave(url);
      if (result.error) { setError(result.error); return; }
      setSavedUrl(url); setDraft(url); setProposedUrl(undefined);
      setNotice("Vxpipe URL updated.");
    } catch {
      setError("Unable to save the Vxpipe URL. Try again. Your saved URL has not changed.");
    } finally { setPending(false); }
  }

  function submit(event: FormEvent) {
    event.preventDefault(); setError(undefined); setNotice(undefined);
    const result = normalizeInstanceUrl(draft);
    if ("error" in result) { setError(result.error); return; }
    if (result.url === savedUrl) { setDraft(result.url); return; }
    if (savedUrl) setProposedUrl(result.url);
    else void save(result.url);
  }

  return <main className="access-page access-narrow installation-settings">
    <h1>Installation</h1>
    <p className="access-lead">Manage the address used by this VxPipe installation. This URL is used by users to access this app and by integrations within the app, such as Telephony and MCPs.</p>
    {state === "loading" ? <p role="status" className="access-message">Loading installation settings…</p> : state === "unavailable" ? <>
      <FormMessage error>Installation settings could not be loaded.</FormMessage>
      <Button onClick={onRetry}>Try again</Button>
    </> : <form className="access-form" onSubmit={submit}>
      <FormField label="Vxpipe URL" type="url" autoComplete="url" spellCheck={false} required
        value={draft} disabled={pending}
        hint="Include https:// and a port if needed. HTTP is allowed for localhost."
        onChange={event => { setDraft(event.target.value); setError(undefined); setNotice(undefined); }} />
      {!proposedUrl && error ? <FormMessage error>{error}</FormMessage> : null}
      {notice ? <FormMessage>{notice}</FormMessage> : null}
      <div className="access-actions"><Button className="access-primary" type="submit" disabled={pending || draft === savedUrl}>{pending ? "Saving…" : "Save changes"}</Button></div>
    </form>}
    {proposedUrl ? <SetupDialog title="Change Vxpipe URL?" busy={pending} onClose={() => { setProposedUrl(undefined); setError(undefined); }}>
      <div className="installation-url-confirm">
        <dl>
          <div><dt>Current URL</dt><dd>{savedUrl}</dd></div>
          <div><dt>New URL</dt><dd>{proposedUrl}</dd></div>
        </dl>
        <p className="access-muted">Update phone-provider webhooks that use this installation’s address. MCP clients may need to reconnect with OAuth. Keep the old address reachable until existing calls end.</p>
        {error ? <FormMessage error>{error}</FormMessage> : null}
        <div className="access-actions">
          <Button type="button" disabled={pending} onClick={() => { setProposedUrl(undefined); setError(undefined); }}>Cancel</Button>
          <Button type="button" className="access-primary" disabled={pending} onClick={() => void save(proposedUrl)}>{pending ? "Saving…" : "Change URL"}</Button>
        </div>
      </div>
    </SetupDialog> : null}
  </main>;
}
