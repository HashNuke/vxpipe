import type { Grant, Membership, Role, Tenant, User } from "./types";

export type ConnectedClient = {
  public_id: string;
  client_name: string;
  resource: string;
  inserted_at: string;
  expires_at: string;
};

export type InstallationSettings = { public_url: string | null; revision: number };

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
type PaginatedUsers = {
  users: User[];
  pagination: { page: number; page_size: number; total: number; total_pages: number };
};
type UserInput = {
  email: string;
  password: string;
  passwordConfirmation: string;
  roleId: string;
  memberships: Membership[];
};
type RoleInput = Pick<Role, "name" | "grants">;

/** Thrown for HTTP/API failures; carries the status and backend error code. */
export class AuthenticationError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly code?: string,
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export function isSessionExpired(error: unknown): boolean {
  return error instanceof AuthenticationError && error.status === 401;
}

export function isForbidden(error: unknown): boolean {
  return error instanceof AuthenticationError && error.status === 403;
}

function errorMessage(status: number, code: unknown): string {
  if (status === 422 && code === "invalid_public_url") return "Enter a valid HTTPS URL. HTTP is allowed for localhost.";
  if (status === 403) return "Your role does not allow this action.";
  if (status === 401 && code === "invalid_credentials")
    return "Email or password is incorrect.";
  if (status === 401) return "Your session expired. Sign in again.";
  if (status === 409 && code === "last_superadmin")
    return "Keep at least one active Superadmin. Add another before changing this account.";
  if (status === 409) return "These details changed elsewhere. Reload and try again.";
  if (status === 422) return "Check the entered details and try again.";
  return "The request could not be completed. Try again.";
}

function apiPath(path: string): string {
  if (!path.startsWith("/api/") && !path.startsWith("/admin/api/") && !path.startsWith("/auth/api/")) {
    throw new Error("Invalid authentication API path");
  }
  return path;
}

export class AuthenticationApi {
  constructor(
    private readonly csrfToken: string,
    private readonly fetchImpl: Fetch = (input, init) => window.fetch(input, init),
  ) {}

  private async request<T>(path: string, method = "GET", body?: unknown): Promise<T> {
    let response: Response;
    try {
      response = await this.fetchImpl(apiPath(path), {
        method,
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          ...(body === undefined ? {} : { "content-type": "application/json" }),
          ...(method === "GET" ? {} : { "x-csrf-token": this.csrfToken }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
    } catch {
      throw new AuthenticationError("The connection is unavailable. Try again.");
    }

    let data: unknown;
    if (response.status !== 204) {
      try {
        data = await response.json();
      } catch {
        throw new AuthenticationError("The server returned an invalid response.", response.status);
      }
    }
    if (!response.ok) {
      const error =
        typeof data === "object" && data !== null && "error" in data
          ? data.error
          : undefined;
      const code =
        typeof error === "object" && error !== null && "code" in error
          ? error.code
          : undefined;
      throw new AuthenticationError(
        errorMessage(response.status, code),
        response.status,
        typeof code === "string" ? code : undefined,
      );
    }
    return data as T;
  }

  connectedClients() {
    return this.request<{ connections: ConnectedClient[] }>("/api/account/connections");
  }

  revokeConnectedClient(id: string) {
    return this.request<void>(`/api/account/connections/${encodeURIComponent(id)}`, "DELETE");
  }

  async logout(): Promise<void> {
    // Form-equivalent POST; the server clears the session and redirects to
    // /auth/login. The caller reloads there so server-rendered guards apply.
    let response: Response;
    try {
      response = await this.fetchImpl("/auth/logout", {
        method: "POST",
        credentials: "same-origin",
        headers: { "x-csrf-token": this.csrfToken },
      });
    } catch {
      throw new AuthenticationError("The connection is unavailable. Try again.");
    }
    if (response.status >= 400) {
      throw new AuthenticationError("Sign-out could not finish. Try again.", response.status);
    }
  }

  setup(email: string, password: string, confirmation: string, proof?: string, publicUrl?: string) {
    return this.request<void>("/auth/api/setup", "POST", {
      email,
      password,
      password_confirmation: confirmation,
      public_url: publicUrl,
      ...(proof ? { proof } : {}),
    });
  }

  login(email: string, password: string) {
    return this.request<void>("/auth/api/login", "POST", { email, password });
  }

  installation() { return this.request<InstallationSettings>("/api/installation"); }

  updateInstallation(publicUrl: string, revision: number) {
    return this.request<InstallationSettings>("/api/installation", "PATCH", { public_url: publicUrl, revision });
  }

  recover(proof: string, email: string, password: string, confirmation: string) {
    return this.request<void>("/auth/api/recover", "POST", {
      proof,
      email,
      password,
      password_confirmation: confirmation,
    });
  }

  status() {
    return this.request<{ status: "pending_first_run" | "pending_operator_proof" | "complete" }>(
      "/auth/api/status",
    );
  }

  session() {
    return this.request<{ user: User; role: Role }>("/admin/api/session");
  }

  users(query: URLSearchParams) {
    const filters = new URLSearchParams();
    for (const [key, value] of query) {
      filters.set(key === "q" ? "query" : key === "role" ? "role_id" : key, value);
    }
    const suffix = filters.size ? `?${filters.toString()}` : "";
    return this.request<PaginatedUsers>(`/api/users${suffix}`);
  }

  user(id: string) {
    return this.request<{ user: User }>(`/api/users/${encodeURIComponent(id)}`);
  }

  createUser(input: UserInput) {
    return this.request<{ user: User }>("/api/users", "POST", {
      email: input.email,
      password: input.password,
      password_confirmation: input.passwordConfirmation,
      role_id: input.roleId,
      memberships: input.memberships.map((item) => ({
        tenant_key: item.tenantId,
        access: item.access,
      })),
    });
  }

  updateUser(id: string, input: Omit<User, "id">) {
    return this.request<{ user: User }>(`/api/users/${encodeURIComponent(id)}`, "PATCH", {
      email: input.email,
      role_id: input.roleId,
      enabled: input.enabled,
      memberships: input.memberships.map((item) => ({
        tenant_key: item.tenantId,
        access: item.access,
      })),
    });
  }

  resetPassword(id: string, password: string, confirmation: string) {
    return this.request<void>(
      `/api/users/${encodeURIComponent(id)}/reset-password`,
      "POST",
      { password, password_confirmation: confirmation },
    );
  }

  async roles(page = 1): Promise<{roles: Role[]; pagination: DirectoryPagination}> {
    const result = await this.request<{roles: Role[]; pagination: DirectoryPagination}>(`/api/roles?page=${page}`);
    if (!Array.isArray(result.roles)) throw invalidDirectoryResponse();
    directoryPageCount(result.pagination, page, result.roles.length);
    return result;
  }

  /**
   * Minimal id/name/kind metadata for `users.read` viewers who cannot list
   * full roles. Entries carry no grants; callers must treat them as
   * read-only display data, never as authority.
   */
  async roleOptions(): Promise<{ roles: Role[] }> {
    const roles: Role[] = [];
    let page = 1;
    let totalPages = 1;
    while (page <= totalPages) {
      const data = await this.request<{ roles?: unknown; pagination?: DirectoryPagination }>(
        `/api/role-options?page=${page}`,
      );
      if (!Array.isArray(data.roles)) throw invalidDirectoryResponse();
      totalPages = directoryPageCount(data.pagination, page, data.roles.length);
      roles.push(...data.roles.map(parseRoleOption));
      page += 1;
    }
    return { roles };
  }

  role(id: string) {
    return this.request<{ role: Role; affected_users: number }>(
      `/api/roles/${encodeURIComponent(id)}`,
    );
  }

  createRole(input: RoleInput) {
    return this.request<{ role: Role }>("/api/roles", "POST", roleBody(input));
  }

  updateRole(id: string, input: RoleInput, expectedRevision?: number) {
    return this.request<{ role: Role }>(
      `/api/roles/${encodeURIComponent(id)}`,
      "PATCH",
      {
        ...roleBody(input),
        ...(expectedRevision === undefined ? {} : { expected_revision: expectedRevision }),
      },
    );
  }

  deleteRole(id: string) {
    return this.request<void>(`/api/roles/${encodeURIComponent(id)}`, "DELETE");
  }

  /**
   * Tenant lookup for the user-form picker. The tenant directory returns
   * `{tenant_key, name}` entries; memberships are keyed by tenant key, so the key
   * doubles as the option id. Follows every server page so no tenant is
   * silently omitted from assignment.
   */
  async tenantOptions(): Promise<{ tenants: Tenant[] }> {
    const tenants: Tenant[] = [];
    let page = 1;
    let totalPages = 1;
    while (page <= totalPages) {
      const data = await this.request<{ items?: unknown; pagination?: DirectoryPagination }>(
        `/api/tenants?page=${page}`,
      );
      if (!Array.isArray(data.items)) throw invalidDirectoryResponse();
      totalPages = directoryPageCount(data.pagination, page, data.items.length);
      tenants.push(...data.items.map(parseTenantOption));
      page += 1;
    }
    return { tenants };
  }

  updateAccount(email: string, currentPassword: string, newPassword?: string, confirmation?: string) {
    return this.request<void>("/admin/api/account", "PATCH", {
      email,
      current_password: currentPassword,
      ...(newPassword
        ? { password: newPassword, password_confirmation: confirmation ?? newPassword }
        : {}),
    });
  }
}

function roleBody(input: RoleInput) {
  return {
    name: input.name,
    grants: input.grants.map((grant: Grant) => ({
      permission: grant.permission,
      scope: grant.scope,
    })),
  };
}

function parseRoleOption(entry: unknown): Role {
  if (typeof entry !== "object" || entry === null) {
    throw new AuthenticationError("The server returned an invalid response.");
  }
  const record = entry as Record<string, unknown>;
  const id = record.id;
  const kind = record.kind;
  if (typeof id !== "string" || id.length === 0 || typeof record.name !== "string") {
    throw new AuthenticationError("The server returned an invalid response.");
  }
  return {
    id,
    name: record.name,
    kind: kind === "superadmin" || kind === "admin" ? kind : null,
    grants: [],
  };
}

function parseTenantOption(entry: unknown): Tenant {
  if (typeof entry !== "object" || entry === null) {
    throw new AuthenticationError("The server returned an invalid response.");
  }
  const record = entry as Record<string, unknown>;
  if (typeof record.tenant_key !== "string" || record.tenant_key.length === 0 || typeof record.name !== "string") {
    throw new AuthenticationError("The server returned an invalid response.");
  }
  return { id: record.tenant_key, key: record.tenant_key, name: record.name };
}

type DirectoryPagination = { page: number; page_size: number; total: number; total_pages: number };

function invalidDirectoryResponse() {
  return new AuthenticationError("The server returned an invalid response.");
}

function directoryPageCount(value: DirectoryPagination | undefined, page: number, count: number): number {
  if (!value || value.page !== page || !Number.isInteger(value.page_size) || value.page_size < 1 || value.page_size > 50 ||
    !Number.isInteger(value.total) || value.total < 0 || value.total_pages !== Math.ceil(value.total / value.page_size) ||
    page > Math.max(1, value.total_pages) || count !== Math.min(value.page_size, Math.max(0, value.total - (page - 1) * value.page_size))) {
    throw invalidDirectoryResponse();
  }
  return value.total_pages;
}
