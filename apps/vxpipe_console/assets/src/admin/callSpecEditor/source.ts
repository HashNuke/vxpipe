import type { CallSpecSource, SourceDocument } from "./types";

export function parseSource(json: string): SourceDocument {
  const source: unknown = JSON.parse(json);
  if (!record(source) || !record(source.participants)) {
    throw new Error("The call spec must be an object with participants.");
  }
  if (source.schema_version !== "20261004.01" && source.schema_version !== "20260915.01") {
    throw new Error("This call spec schema version is not supported by the editor.");
  }
  const readOnly = source.schema_version === "20260915.01";
  return {
    source: source as CallSpecSource,
    readOnly,
    ...(readOnly ? { notice: "Schema 20260915.01 opens read-only. Its source is preserved without migration." } : {}),
  };
}

export function serializeSource(document: SourceDocument): string {
  return JSON.stringify(document.source, null, 2);
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
