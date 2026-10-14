import { classNames } from "./classNames";
import type { CallSpecSummary } from "./callSpecTypes";
import { getCallSpecStatus } from "./getCallSpecStatus";

const labels = {
  draft: "Draft",
  published: "Published",
};

export function CallSpecStatusBadge({
  callSpec,
}: {
  callSpec: CallSpecSummary;
}) {
  const status = getCallSpecStatus(callSpec);
  const hasChanges = status === "published" && callSpec.latestRevision !== callSpec.publishedRevision;
  const title =
    status === "published"
      ? `Published version v${callSpec.publishedRevision}`
      : "No version has been published";
  return (
    <span className="inline-flex flex-col items-start gap-1">
      <span
        className={classNames(
          "inline-flex min-h-6 items-center rounded-full border px-2 font-mono text-xs font-bold uppercase tracking-[0.04em]",
          status === "published" &&
            "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]",
          status === "draft" &&
            "border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] text-[var(--admin-amber)]",
        )}
        title={title}
      >
        {labels[status]}
      </span>
      {hasChanges ? <span className="text-xs text-[var(--admin-muted)]" title={`Latest version v${callSpec.latestRevision}; published version v${callSpec.publishedRevision}`}>Unpublished changes</span> : null}
    </span>
  );
}
