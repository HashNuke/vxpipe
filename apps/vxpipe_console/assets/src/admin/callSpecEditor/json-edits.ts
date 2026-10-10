import { editSource } from "./editSource";
import { parseSourceJson } from "./source-json";
import { parseSource } from "./source";
import type { Participant, SourceDocument } from "./types";
import { validateSource } from "./validation";

export function applyJson(document: SourceDocument, text: string, participantKey?: string): SourceDocument {
  if (document.readOnly || document.source.schema_version !== "20261004.01") throw new Error("This call spec is read-only.");
  let value: unknown;
  try { value = parseSourceJson(text); }
  catch { throw new Error("Enter valid JSON before applying changes."); }
  let next: SourceDocument;
  if (participantKey === undefined) {
    next = parseSource(text);
    if (next.source.schema_version !== document.source.schema_version) throw new Error("Keep the current schema_version when editing JSON.");
  } else {
    if (!Object.hasOwn(document.source.participants, participantKey)) throw new Error("This participant no longer exists. Copy your edits before discarding them.");
    next = editSource(document, (source) => { source.participants[participantKey] = value as Participant; });
  }
  const previous = new Set(validateSource(document.source).map((issue) => JSON.stringify(issue)));
  const issues = validateSource(next.source).filter((issue) => participantKey === undefined ||
    (issue.path[0] === "participants" && issue.path[1] === participantKey) || !previous.has(JSON.stringify(issue)));
  if (issues.length) throw new Error(issues.slice(0, 5).map((issue) => `${issue.path.join(".") || "Call spec"}: ${issue.reason}`).join("\n"));
  if (Boolean(next.source.outgoing_call) !== Boolean(document.source.outgoing_call)) throw new Error("Call direction cannot be changed. Create a new call spec instead.");
  return next;
}
