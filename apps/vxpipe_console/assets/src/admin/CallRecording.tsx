import { useSyncExternalStore } from "react";
import type { CallConsoleController } from "@vxpipe/core";

export function CallRecording({
  tenantKey,
  callId,
  controller,
}: {
  tenantKey: string;
  callId: string;
  controller: CallConsoleController;
}) {
  const snapshot = useSyncExternalStore(
    controller.details.subscribe,
    controller.details.getSnapshot,
    controller.details.getSnapshot,
  );
  const recording = snapshot.call.recording ?? { status: "not_requested" as const };
  const href = `/api/tenants/${encodeURIComponent(tenantKey)}/calls/${encodeURIComponent(callId)}/recording.mka`;

  if (recording.status === "recorded") {
    return (
      <a
        className="shrink-0 text-xs font-medium text-[var(--admin-ink)] underline underline-offset-2 hover:no-underline"
        download={`call-${callId}.mka`}
        href={href}
      >
        Download recording
      </a>
    );
  }

  if (recording.status === "unavailable") {
    return (
      <span className="shrink-0 text-xs text-[var(--admin-muted)]">
        Recording unavailable
      </span>
    );
  }

  return (
    <span className="shrink-0 text-xs text-[var(--admin-muted)]">Not recorded</span>
  );
}
