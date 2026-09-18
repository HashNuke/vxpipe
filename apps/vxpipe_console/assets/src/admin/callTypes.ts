import type { PaginationModel } from "./tenantTypes";
import type { TenantContext } from "./callSpecTypes";

export type CallSpecContext = {
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
  callSpecId: string;
  callSpecName: string | null;
  callSpecRevision: number;
  state: CallDirectoryState;
  createdAt: string;
};

export type CallSummary = {
  id: string;
  callSpecId: string;
  callSpecName: string | null;
  callSpecRevision: number;
  state: CallLifecycleState;
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
  terminalReason: string | null;
  archiveState: CallArchiveState;
};

type TenantCallsContext = {
  tenant: TenantContext;
  callSpecs: Array<Pick<CallSpecContext, "id" | "name">>;
  callSpecsTruncated?: boolean;
  selectedCallSpecId: string | null;
};

export type CallSpecCallsPageState = TenantCallsContext &
  (
    | { status: "loading" }
    | { status: "unavailable"; message: string }
    | {
        status: "ready";
        calls: CallDirectoryItem[];
        pagination: PaginationModel | null;
      }
  );
