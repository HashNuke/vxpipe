import type { SourceDocument, SourceIssue } from "./types";
export type InspectorProps = {
  document: SourceDocument;
  onChange: (document: SourceDocument) => void;
  issues?: SourceIssue[];
};
export type NamedService = { key: string; name: string };
export type EditorLookups = {
  telephonyServices: NamedService[];
  credentialNames: Record<string, string[]>;
  mcpIntegrations: string[];
};
