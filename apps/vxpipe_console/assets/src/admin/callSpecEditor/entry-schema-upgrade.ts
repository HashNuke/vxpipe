import type { CallSpecSource, SourceDocument } from "./types";

export function entryUpgradeNotice(source: CallSpecSource): string {
  const key = source.incoming_call?.caller ?? source.outgoing_call?.callee;
  const participant = key ? source.participants[key] : undefined;
  const changes = ["Upgrade this draft to manage Entry in Call settings."];
  if (source.opening_audio?.type === "text") changes.push("The opening voice will use the call’s default text-to-speech model.");
  if (participant?.capabilities) changes.push("Entry transcription will use the call defaults.");
  if (participant?.while_present) {
    changes.push("Upgrading removes Entry’s media overrides, including any recording or routing restrictions. Review the call media policy before publishing.");
  }
  return changes.join(" ");
}

export function upgradeEntrySettings(previous: CallSpecSource): SourceDocument {
  if (previous.schema_version !== "20261004.01") throw new Error("Only directional call specs can use this upgrade.");
  const source = structuredClone(previous);
  const key = source.incoming_call?.caller ?? source.outgoing_call?.callee;
  const entry = key ? source.participants[key] : undefined;
  if (entry) {
    delete entry.capabilities;
    delete entry.while_present;
  }
  if (source.opening_audio?.type === "text") delete source.opening_audio.text_to_speech;
  source.schema_version = "20261125.01";
  return { source, readOnly: false };
}
