import type { DefinitionSummary } from "./definitionTypes";

export function getDefinitionStatus(
  definition: Pick<DefinitionSummary, "latestRevision" | "publishedRevision">,
) {
  if (definition.publishedRevision === null) return "draft" as const;
  if (definition.publishedRevision === definition.latestRevision) {
    return "published" as const;
  }
  return "draft-changes" as const;
}
