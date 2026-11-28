import type { CallSpecSource, SourceDocument } from "./types";

export const editableSchemaVersions = ["20261128.01", "20261125.01"];

export function editSource(document: SourceDocument, change: (source: CallSpecSource) => void): SourceDocument {
  if (document.readOnly || !editableSchemaVersions.includes(document.source.schema_version)) {
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
