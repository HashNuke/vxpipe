export type CallSpecPublication = {
  version: number | null;
  revision: number | null;
  unpublishedChanges: boolean;
  draftSavedAt: string | null;
  history: { version: number; publishedAt: string }[];
};

const object = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0;
const date = (value: unknown): value is string => typeof value === "string" && Number.isFinite(Date.parse(value));

/** Undefined supports existing custom repository adapters without fabricated history. */
export function parseCallSpecPublication(value: unknown): CallSpecPublication | undefined {
  if (value === undefined) return undefined;
  if (!object(value) || !(value.version === null || positive(value.version)) ||
    !(value.revision === null || positive(value.revision)) || (value.version === null) !== (value.revision === null) ||
    typeof value.unpublished_changes !== "boolean" || !date(value.draft_saved_at) ||
    !Array.isArray(value.history) || value.history.length > 3) throw new Error("Invalid publication status");
  let previous = Infinity;
  const history = value.history.map(entry => {
    if (!object(entry) || !positive(entry.version) || !date(entry.published_at) || entry.version >= previous ||
      value.version === null || entry.version > (value.version as number)) throw new Error("Invalid publication history");
    previous = entry.version;
    return { version: entry.version, publishedAt: entry.published_at };
  });
  if (value.version !== null && history.at(0)?.version !== value.version) throw new Error("Missing live publication");
  return { version: value.version, revision: value.revision, unpublishedChanges: value.unpublished_changes, draftSavedAt: value.draft_saved_at, history };
}

export function publicationLabel(version: number | null, changes: boolean): string {
  return version === null ? "Draft" : `v${version}${changes ? " · Unpublished changes" : " Published"}`;
}

export const publicationChangeClasses = "border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] text-[var(--admin-amber)]";
export const publicationLiveClasses = "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]";
