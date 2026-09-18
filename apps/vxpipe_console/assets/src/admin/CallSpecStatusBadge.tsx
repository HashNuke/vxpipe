import { classNames } from "./classNames";
import type { CallSpecSummary } from "./callSpecTypes";
import { getCallSpecStatus } from "./getCallSpecStatus";

const labels = {
  draft: "Draft",
  published: "Published",
  "draft-changes": "Draft changes",
};

export function CallSpecStatusBadge({
  callSpec,
}: {
  callSpec: CallSpecSummary;
}) {
  const status = getCallSpecStatus(callSpec);
  const title =
    status === "published"
      ? `Published version v${callSpec.publishedRevision}`
      : status === "draft-changes"
        ? `Latest version v${callSpec.latestRevision}; published version v${callSpec.publishedRevision}`
        : "No version has been published";
  return (
    <span
      className={classNames(
        "inline-flex min-h-6 items-center rounded-full border px-2 font-mono text-xs font-bold uppercase tracking-[0.04em]",
        status === "published" &&
          "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]",
        status === "draft" &&
          "border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] text-[var(--admin-amber)]",
        status === "draft-changes" &&
          "border-[var(--admin-blue)]/35 bg-[var(--admin-blue-soft)] text-[var(--admin-blue)]",
      )}
      title={title}
    >
      {labels[status]}
    </span>
  );
}
