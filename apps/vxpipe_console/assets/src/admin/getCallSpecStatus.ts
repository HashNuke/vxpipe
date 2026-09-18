import type { CallSpecSummary } from "./callSpecTypes";

export function getCallSpecStatus(
  callSpec: Pick<CallSpecSummary, "latestRevision" | "publishedRevision">,
) {
  if (callSpec.publishedRevision === null) return "draft" as const;
  if (callSpec.publishedRevision === callSpec.latestRevision) {
    return "published" as const;
  }
  return "draft-changes" as const;
}
