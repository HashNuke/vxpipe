import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from "react";
import { customPreset, draftFor, type Draft, type Scenario } from "./fixtures";

type Status = "idle" | "waiting" | "resource" | "oauth" | "ready" | "failed";
function validUrl(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password && !url.hash;
  } catch { return false; }
}

/** Local preview of one backend discovery operation. Never fetches the entered URL. */
export function useUrlDiscovery(draft: Draft, setDraft: Dispatch<SetStateAction<Draft>>, active: boolean, scenario: Scenario) {
  const [request, setRequest] = useState(() => ({ endpoint: draft.auth === "auto" && draft.preset.id === "custom" ? draft.endpoint : "", attempt: 0 }));
  const [status, setStatus] = useState<Status>("idle");
  const edited = useRef(new Set<string>());
  useEffect(() => {
    if (!active || !validUrl(request.endpoint)) return;
    const endpoint = request.endpoint.trim();
    const origin = new URL(endpoint).origin;
    const apply = (patch: Partial<Draft>) => setDraft(current => current.endpoint.trim() !== endpoint ? current : {
      ...current,
      ...Object.fromEntries(Object.entries(patch).filter(([key]) => !edited.current.has(key))),
    });
    const timers = [
      window.setTimeout(() => setStatus("resource"), 350),
      window.setTimeout(() => {
        if (scenario === "discovery-failed") { setStatus("failed"); return; }
        if (scenario === "discovery-no-auth") {
          apply({ auth: "none" });
          setStatus("ready");
        } else setStatus("oauth");
      }, 750),
      window.setTimeout(() => {
        if (scenario === "discovery-failed" || scenario === "discovery-no-auth") return;
        apply({ auth: "cimd", issuer: origin, authorizationUrl: `${origin}/oauth/authorize`,
          tokenUrl: `${origin}/oauth/token`, revocationUrl: `${origin}/oauth/revoke`,
          scopes: "tools:read tools:invoke", resource: endpoint });
        setStatus("ready");
      }, 1150),
    ];
    return () => timers.forEach(window.clearTimeout);
  }, [active, request, scenario, setDraft]);

  function update(patch: Partial<Draft>) {
    if (patch.endpoint !== undefined && patch.endpoint !== draft.endpoint && draft.preset.id === "custom") {
      edited.current.clear();
      setDraft({ ...draftFor(customPreset), endpoint: patch.endpoint });
      setStatus(validUrl(patch.endpoint) ? "waiting" : "idle");
      setRequest({ endpoint: patch.endpoint, attempt: 0 });
    } else {
      Object.keys(patch).forEach(key => edited.current.add(key));
      setDraft(current => ({ ...current, ...patch }));
    }
  }
  function retry() {
    setStatus("waiting");
    setRequest(current => ({ endpoint: draft.endpoint, attempt: current.attempt + 1 }));
  }
  function reset() {
    setStatus("idle");
    setRequest({ endpoint: "", attempt: 0 });
    edited.current.clear();
  }
  return { status, update, retry, reset };
}
