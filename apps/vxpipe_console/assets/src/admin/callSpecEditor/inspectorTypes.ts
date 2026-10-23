import type { IssueRequest } from "./issue-context";
import type { SourceDocument, SourceIssue, ToolSelection } from "./types";
export type InspectorProps = {
  document: SourceDocument;
  onChange: (document: SourceDocument) => void;
  issues?: SourceIssue[];
  focusRequest?: IssueRequest;
};
export type NamedService = { key: string; name: string; provider?: "twilio" | "telnyx" };
export type PhoneNumber = { id: string; number: string; name: string; available: boolean; assignedTo: string[] };
export type PhoneNumberPage = { numbers: PhoneNumber[]; nextPage: string | null };
export type PhoneNumberLoader = (service: string, search: string, page: string | null, signal: AbortSignal) => Promise<PhoneNumberPage>;
export type EditorLookups = {
  phoneNumbers?: PhoneNumberLoader;
  telephonyServices: NamedService[];
  credentialNames: Record<string, string[]>;
  mcpIntegrations: string[];
  toolCatalog?: ToolCatalog;
};
export type AvailableTool = Pick<ToolSelection, "type" | "tool" | "integration"> & { description: string };
export type ToolCatalog = { tools: AvailableTool[]; mcpAvailable: boolean };
