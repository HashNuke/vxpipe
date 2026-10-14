import type { CallSpecSummary } from "./callSpecTypes";

export function getCallSpecStatus(
  callSpec: Pick<CallSpecSummary, "latestRevision" | "publishedRevision">,
) {
  return callSpec.publishedRevision === null ? "draft" as const : "published" as const;
}
