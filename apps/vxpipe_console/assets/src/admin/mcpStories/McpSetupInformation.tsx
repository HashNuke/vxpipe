import { ArrowUpRight } from "lucide-react";
import type { Preset } from "./fixtures";

function resourceUrl(value?: string) {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? value : undefined;
  } catch { return undefined; }
}

export function McpSetupInformation({ preset }: { preset: Preset }) {
  const setupUrl = resourceUrl(preset.setupUrl);
  const documentationUrl = resourceUrl(preset.docs);
  const notes = preset.setupNotes?.trim();
  if (!notes && !setupUrl && !documentationUrl) return null;
  return <div className="mcp-provider-note">
    {notes && <p>{notes}</p>}
    {(setupUrl || documentationUrl) && <div className="mcp-resource-links">
      {setupUrl && <a href={setupUrl} target="_blank" rel="noopener noreferrer">Setup<ArrowUpRight size={14} aria-hidden /></a>}
      {documentationUrl && <a href={documentationUrl} target="_blank" rel="noopener noreferrer">Documentation<ArrowUpRight size={14} aria-hidden /></a>}
    </div>}
  </div>;
}
