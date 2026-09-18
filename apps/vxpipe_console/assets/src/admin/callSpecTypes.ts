import type { PaginationModel } from "./tenantTypes";

export type TenantContext = {
  key: string;
  name: string;
};

export type DefinitionSummary = {
  id: string;
  name: string | null;
  latestRevision: number;
  publishedRevision: number | null;
  callCount: number;
  updatedAt: string;
};

export type TenantDefinitionsPageState =
  | { status: "loading"; tenant: TenantContext }
  | { status: "unavailable"; tenant: TenantContext; message: string }
  | {
      status: "ready";
      tenant: TenantContext;
      definitions: DefinitionSummary[];
      pagination: PaginationModel | null;
    };
