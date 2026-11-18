import type { CallSpecSummary } from "./callSpecTypes";
import { publicationChangeClasses, publicationLabel } from "./callSpecPublication";

export function CallSpecStatusBadge({ callSpec }: { callSpec: CallSpecSummary }) {
  const version = callSpec.publishedVersion === undefined ? callSpec.publishedRevision : callSpec.publishedVersion;
  const changes = callSpec.unpublishedChanges ?? (callSpec.latestRevision !== callSpec.publishedRevision);
  return <span className={`inline-flex min-h-7 items-center rounded-full border px-2.5 text-xs font-medium whitespace-nowrap ${version !== null && changes ? publicationChangeClasses : "border-[var(--admin-line)] text-[var(--admin-text)]"}`}>
    {publicationLabel(version, changes)}
  </span>;
}
