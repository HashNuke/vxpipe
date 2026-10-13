import { expect, test, vi } from "vitest";
import { AuthenticationApi } from "./authenticationApi";

test("sends chosen credentials only in a CSRF-protected same-origin create request", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ user: { id: "user-1" } }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.createUser({
    email: "person@example.test",
    password: "example long password",
    passwordConfirmation: "example long password",
    roleId: "role-1",
    memberships: [{ tenantId: "tenant-1", access: "read" }],
  });

  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/users",
    expect.objectContaining({
      method: "POST",
      credentials: "same-origin",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
      body: JSON.stringify({
        email: "person@example.test",
        password: "example long password",
        password_confirmation: "example long password",
        role_id: "role-1",
        memberships: [{ tenant_id: "tenant-1", access: "read" }],
      }),
    }),
  );
});

test("server denial becomes an actionable error without echoing a submitted password", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ error: { code: "forbidden", detail: "secret-value" } }), {
      status: 403,
    }),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await expect(api.resetPassword("user-1", "secret-value", "secret-value")).rejects.toThrow(
    "Your role does not allow this action.",
  );
});

test("passes directory filters to the server before pagination", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ users: [], pagination: { page: 2, page_size: 20, total: 0, total_pages: 0 } }), {
      status: 200,
    }),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);
  await api.users(new URLSearchParams({ q: "member", role: "role-1", page: "2" }));
  expect(fetchImpl.mock.calls[0][0]).toBe(
    "/admin/api/users?q=member&role=role-1&page=2",
  );
});

test("signs out with a CSRF-protected POST to the logout endpoint", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(new Response("", { status: 302 }));
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.logout();

  expect(fetchImpl).toHaveBeenCalledWith(
    "/auth/logout",
    expect.objectContaining({
      method: "POST",
      credentials: "same-origin",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
    }),
  );
});

test("reports failed session revocation instead of claiming sign-out succeeded", async () => {
  const api = new AuthenticationApi(
    "csrf-token",
    vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: { code: "unavailable" } }), { status: 503 })),
  );

  await expect(api.logout()).rejects.toThrow(/unavailable|try again/i);
});

test("submits a local recovery proof and confirmed replacement password", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.recover("local-proof", "owner@example.test", "replacement passphrase", "replacement passphrase");

  expect(fetchImpl).toHaveBeenCalledWith(
    "/auth/api/recover",
    expect.objectContaining({
      method: "POST",
      credentials: "same-origin",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
      body: JSON.stringify({
        proof: "local-proof",
        email: "owner@example.test",
        password: "replacement passphrase",
        password_confirmation: "replacement passphrase",
      }),
    }),
  );
});

test("maps minimal role options without granting authority", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(
      JSON.stringify({
        role_options: [
          { public_id: "role-1", name: "Superadmin", kind: "superadmin" },
          { public_id: "role-2", name: "Member", kind: "member" },
        ],
      }),
      { status: 200 },
    ),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  const { roles } = await api.roleOptions();

  expect(roles).toEqual([
    { id: "role-1", name: "Superadmin", description: "", kind: "superadmin", grants: [] },
    { id: "role-2", name: "Member", description: "", kind: null, grants: [] },
  ]);
});

test("maps the tenant directory across pages for tenant assignment", async () => {
  const page = (key: string, pageNumber: number) => ({
    tenants: [{ key, name: `Tenant ${key}`, created_at: "2026-09-17T01:00:00Z" }],
    pagination: { page: pageNumber, page_size: 1, total: 2, total_pages: 2 },
  });
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    Promise.resolve(
      new Response(JSON.stringify(String(input).endsWith("page=2") ? page("b", 2) : page("a", 1)), {
        status: 200,
      }),
    ),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  const { tenants } = await api.tenantOptions();

  expect(tenants).toEqual([
    { id: "a", key: "a", name: "Tenant a" },
    { id: "b", key: "b", name: "Tenant b" },
  ]);
});

test("tenant options follow the whole directory instead of stopping at ten pages", async () => {
  const totalPages = 12;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const pageNumber = Number(new URL(String(input), "http://console.invalid").searchParams.get("page"));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          tenants: [{ key: `tenant-${pageNumber}`, name: `Tenant ${pageNumber}` }],
          pagination: { page: pageNumber, page_size: 1, total: totalPages, total_pages: totalPages },
        }),
        { status: 200 },
      ),
    );
  });
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  const { tenants } = await api.tenantOptions();

  expect(tenants).toHaveLength(totalPages);
  expect(tenants[totalPages - 1]).toEqual({
    id: `tenant-${totalPages}`,
    key: `tenant-${totalPages}`,
    name: `Tenant ${totalPages}`,
  });
});

test("sends the server role revision for optimistic updates", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ role: { id: "role-1", revision: 4 } }), { status: 200 }),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.updateRole("role-1", { name: "Support", description: "", grants: [] }, 3);

  expect(JSON.parse(String(fetchImpl.mock.calls[0][1]?.body))).toMatchObject({
    expected_revision: 3,
  });
});

test("last-superadmin conflicts explain the protection rule", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ error: { code: "last_superadmin" } }), { status: 409 }),
  );
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await expect(
    api.updateUser("user-1", { email: "owner@example.test", roleId: "role-1", enabled: false, memberships: [] }),
  ).rejects.toThrow(/at least one active Superadmin/);
});

test("account password changes send the server-required confirmation", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.updateAccount(
    "owner@example.test",
    "current passphrase here",
    "a brand new passphrase",
    "a brand new passphrase",
  );

  expect(JSON.parse(String(fetchImpl.mock.calls[0][1]?.body))).toEqual({
    email: "owner@example.test",
    current_password: "current passphrase here",
    password: "a brand new passphrase",
    password_confirmation: "a brand new passphrase",
  });
});

test("account email changes omit password fields", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
  const api = new AuthenticationApi("csrf-token", fetchImpl);

  await api.updateAccount("owner@example.test", "current passphrase here");

  expect(JSON.parse(String(fetchImpl.mock.calls[0][1]?.body))).toEqual({
    email: "owner@example.test",
    current_password: "current passphrase here",
  });
});
