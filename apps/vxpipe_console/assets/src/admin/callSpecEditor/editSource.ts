import type { CallSpecSource, SourceDocument } from "./types";

export function editSource(document: SourceDocument, change: (source: CallSpecSource) => void): SourceDocument {
  if (document.readOnly || document.source.schema_version !== "20261004.01") {
    throw new Error("This historical call spec is read-only.");
  }
  const source = structuredClone(document.source);
  change(source);
  return { ...document, source };
}

export function requireIdentifier(key: string): void {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(key)) {
    throw new Error("Use 1–128 letters, numbers, underscores or hyphens for the key.");
  }
}
