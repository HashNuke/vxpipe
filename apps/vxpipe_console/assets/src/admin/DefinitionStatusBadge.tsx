import { classNames } from "./classNames";
import type { DefinitionSummary } from "./definitionTypes";
import { getDefinitionStatus } from "./getDefinitionStatus";

const labels = {
  draft: "Draft",
  published: "Published",
  "draft-changes": "Draft changes",
};

export function DefinitionStatusBadge({
  definition,
}: {
  definition: DefinitionSummary;
}) {
  const status = getDefinitionStatus(definition);
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
    >
      {labels[status]}
    </span>
  );
}
