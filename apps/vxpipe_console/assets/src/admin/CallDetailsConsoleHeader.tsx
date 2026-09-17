import { AlertTriangle } from "lucide-react";

import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";
import { CallIdentity } from "./CallIdentity";

export function CallDetailsConsoleHeader({
  breadcrumbs,
  callId,
  definitionRevision,
  incomplete,
}: {
  breadcrumbs: BreadcrumbItem[];
  callId: string;
  definitionRevision: number | null;
  incomplete: boolean;
}) {
  return (
    <div className="flex min-w-0 items-center gap-3">
      <h1 className="sr-only">Call details</h1>
      <Breadcrumbs compact items={breadcrumbs} />
      <div className="flex min-w-0 max-w-[48%] shrink items-center gap-3 sm:max-w-[58%]">
        {incomplete ? (
          <span
            className="inline-flex shrink-0 items-center gap-1 text-[var(--admin-amber)]"
            role="status"
            title="This call history may be incomplete."
          >
            <AlertTriangle aria-hidden="true" className="size-3" />
            Partial history
          </span>
        ) : null}
        <CallIdentity
          callId={callId}
          definitionRevision={definitionRevision}
        />
      </div>
    </div>
  );
}
