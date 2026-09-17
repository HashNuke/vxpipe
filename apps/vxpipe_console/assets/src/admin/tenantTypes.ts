export type TenantSummary = {
  key: string;
  name: string;
  createdAt: string;
};

export type PaginationModel = {
  label: string;
  hasPrevious: boolean;
  hasNext: boolean;
};

export type TenantsPageState =
  | { status: "loading" }
  | { status: "unavailable"; message: string }
  | {
      status: "ready";
      tenants: TenantSummary[];
      pagination: PaginationModel | null;
    };
