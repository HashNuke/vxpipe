import type { PaginationModel } from "./tenantTypes";
import type { TenantContext } from "./definitionTypes";

export type DefinitionContext = {
  id: string;
  name: string | null;
  latestRevision: number;
  publishedRevision: number | null;
};

export type CallLifecycleState =
  | "prepared"
  | "admitting"
  | "running"
  | "ended"
  | "failed";

export type CallArchiveState = "complete" | "incomplete" | "unconfirmed";

export type CallDirectoryState = "ongoing" | "ended";

export type CallDirectoryItem = {
  id: string;
  definitionId: string;
  definitionName: string | null;
  definitionRevision: number;
  state: CallDirectoryState;
  createdAt: string;
};

export type CallSummary = {
  id: string;
  definitionId: string;
  definitionName: string | null;
  definitionRevision: number;
  state: CallLifecycleState;
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
  terminalReason: string | null;
  archiveState: CallArchiveState;
};

type TenantCallsContext = {
  tenant: TenantContext;
  definitions: Array<Pick<DefinitionContext, "id" | "name">>;
  definitionOptionsTruncated?: boolean;
  selectedDefinitionId: string | null;
};

export type DefinitionCallsPageState = TenantCallsContext &
  (
    | { status: "loading" }
    | { status: "unavailable"; message: string }
    | {
        status: "ready";
        calls: CallDirectoryItem[];
        pagination: PaginationModel | null;
      }
  );
