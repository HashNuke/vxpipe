import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "../Button";
import { FormMessage } from "./FormField";
import { AuthenticationError, type DiagnosticsSettings } from "./authenticationApi";

export type DiagnosticsSettingsApi = {
  diagnosticsSettings(): Promise<DiagnosticsSettings>;
  updateDiagnosticsSettings(enabled: boolean, revision: number): Promise<DiagnosticsSettings>;
};

function checked(value: DiagnosticsSettings): DiagnosticsSettings {
  if (typeof value?.enabled !== "boolean" || !Number.isSafeInteger(value.revision) || value.revision < 0) {
    throw new Error("Diagnostics settings could not be read.");
  }
  return value;
}

export function DiagnosticsSettingsControl({ api, onSessionExpired }: {
  api: DiagnosticsSettingsApi; onSessionExpired?: () => void;
}) {
  const [settings, setSettings] = useState<DiagnosticsSettings>();
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState(false);
  const [needsReload, setNeedsReload] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const generation = useRef(0);

  const load = useCallback(async () => {
    const request = ++generation.current;
    setLoading(true); setSettings(undefined); setError(undefined); setNotice(undefined);
    setNeedsReload(false); setPending(false);
    try {
      const value = checked(await api.diagnosticsSettings());
      if (request === generation.current) setSettings(value);
    } catch (error) {
      if (request !== generation.current) return;
      if (error instanceof AuthenticationError && error.status === 401) onSessionExpired?.();
      setError("Diagnostics settings could not be loaded. Try again.");
    } finally {
      if (request === generation.current) setLoading(false);
    }
  }, [api, onSessionExpired]);

  const retire = useCallback(() => { generation.current++; }, []);
  useEffect(() => {
    void load();
    return retire;
  }, [load, retire]);

  async function save(enabled: boolean) {
    if (!settings || pending || needsReload) return;
    const request = generation.current;
    setPending(true); setError(undefined); setNotice(undefined);
    try {
      const value = checked(await api.updateDiagnosticsSettings(enabled, settings.revision));
      if (request !== generation.current) return;
      setSettings(value); setNotice("Diagnostics setting saved.");
    } catch (error) {
      if (request !== generation.current) return;
      if (error instanceof AuthenticationError && error.status === 401) onSessionExpired?.();
      const stale = error instanceof AuthenticationError && error.status === 409;
      setNeedsReload(true);
      setError(stale ? "This setting changed elsewhere. Reload before saving again." : "Could not confirm this change. Reload diagnostics settings to check the saved value.");
    } finally {
      if (request === generation.current) setPending(false);
    }
  }

  return <div className="access-form">
    <p className="access-muted">Compare estimated speech end with speech recognition turn timing. Existing Silero VAD results are reused when available.</p>
    {loading ? <p role="status">Loading diagnostics settings…</p> : settings ? <>
      <label className="installation-benchmark-control">
        <input type="checkbox" checked={settings.enabled} disabled={pending || needsReload}
          onChange={event => void save(event.target.checked)} aria-describedby="benchmark-setting-status" />
        <span>Benchmark using Silero VAD</span>
      </label>
      <p id="benchmark-setting-status" className="access-muted">Last confirmed setting: {settings.enabled ? "On" : "Off"}. {settings.collection_status === "applying" ? "Applying setting to calls…" : settings.collection_status === "applied" ? "Setting applied." : "Collection status unavailable."}</p>
      {pending ? <p role="status">Saving diagnostics setting…</p> : null}
      {notice ? <FormMessage>{notice}</FormMessage> : null}
    </> : null}
    {error ? <FormMessage error>{error}</FormMessage> : null}
    {!loading && (!settings || needsReload) ? <Button onClick={() => void load()}>Reload diagnostics settings</Button> : null}
  </div>;
}
