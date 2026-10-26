import { CalendarDays, FileText, Plug, Sheet, Users } from "lucide-react";
import { useState } from "react";
import type { Preset } from "./fixtures";

export function McpServiceIcon({ preset }: { preset: Preset }) {
  const [failedLogo, setFailedLogo] = useState<string>();
  const Icon = {
    calendar: CalendarDays,
    sheet: Sheet,
    document: FileText,
    crm: Users,
    custom: Plug,
  }[preset.icon];
  return (
    <span className={`mcp-service-icon mcp-service-icon--${preset.icon}`}>
      {preset.logo && failedLogo !== preset.logo ? <img src={preset.logo} alt="" referrerPolicy="no-referrer" onError={() => setFailedLogo(preset.logo)} /> : <Icon size={20} aria-hidden />}
    </span>
  );
}
