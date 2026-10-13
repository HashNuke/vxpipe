import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, expect, test, vi, type Mock } from "vitest";

import { App } from "./test/ResourceApp";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});

const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

const noContent = () => Promise.resolve(new Response(null, { status: 204 }));

test("local Superadmin recovery signs in after a valid proof", async () => {
  window.history.replaceState({}, "", "/auth/recover");
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/auth/api/status") return response({ status: "complete" });
    if (path === "/auth/api/recover") return response({ ok: true });
    return response({}, 404);
  });

  const authenticated = vi.fn();
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} onAuthenticated={authenticated} />);
  expect(await screen.findByRole("heading", { name: "Recover Superadmin access" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "owner@example.test" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "replacement passphrase" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "replacement passphrase" } });
  fireEvent.change(screen.getByLabelText("Local recovery proof"), { target: { value: "local-proof" } });
  fireEvent.click(screen.getByRole("button", { name: /Recover access/ }));

  await waitFor(() => expect(authenticated).toHaveBeenCalledOnce());
  // A full document load obtains the new session CSRF token before any writes.
  expect(window.location.pathname).toBe("/auth/recover");
  expect(fetchImpl).toHaveBeenCalledWith(
    "/auth/api/recover",
    expect.objectContaining({ method: "POST", headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }) }),
  );
});

const superadminRole = {
  id: "role-super",
  name: "Superadmin",
  description: "",
  kind: "superadmin",
  grants: [],
  revision: 1,
};
const adminRole = {
  id: "role-admin",
  name: "Admin",
  description: "",
  kind: "admin",
  grants: [],
  revision: 1,
};
const memberRole = {
  id: "role-member",
  name: "Tenant Member",
  description: "",
  kind: null,
  grants: [{ permission: "calls.read", scope: "assigned_tenants" }],
  revision: 2,
};
const owner = {
  id: "user-1",
  email: "owner@example.test",
  roleId: "role-super",
  enabled: true,
  memberships: [],
};
const member = {
  id: "user-2",
  email: "member@example.test",
  roleId: "role-member",
  enabled: true,
  memberships: [{ tenantId: "acme_demo_000001", access: "read" }],
};
const tenantDirectory = {
  tenants: [{ key: "acme_demo_000001", name: "Acme", created_at: "2026-09-17T01:00:00Z" }],
  pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
};
const userPage = (users: unknown[]) => ({
  users,
  pagination: { page: 1, page_size: 25, total: users.length, total_pages: 1 },
});

function sessionFetch(role = superadminRole, user = owner) {
  const fetchImpl: Mock<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>> = vi.fn(
    (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === "/admin/api/session") return response({ user, role });
      if (path === "/admin/api/roles")
        return response({ roles: [superadminRole, adminRole, memberRole] });
      if (path.startsWith("/admin/api/users")) return response(userPage([owner, member]));
      if (path.startsWith("/admin/api/tenants")) return response(tenantDirectory);
      if (path === "/auth/logout") return response({ ok: true });
      return response({}, 404);
    },
  );
  return fetchImpl;
}

test("account route saves email with current-password confirmation and CSRF", async () => {
  window.history.replaceState({}, "", "/account");
  const fetchImpl = sessionFetch();
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByRole("heading", { name: "Your account" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Email"), {
    target: { value: "new.owner@example.test" },
  });
  fireEvent.change(screen.getByLabelText("Current password"), {
    target: { value: "an example passphrase" },
  });
  fetchImpl.mockImplementationOnce((input: RequestInfo | URL) => {
    expect(String(input)).toBe("/admin/api/account");
    return noContent();
  });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

  await waitFor(() =>
    expect(fetchImpl).toHaveBeenCalledWith(
      "/admin/api/account",
      expect.objectContaining({
        method: "PATCH",
        headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
      }),
    ),
  );
  const call = fetchImpl.mock.calls.find((args) => String(args[0]) === "/admin/api/account");
  expect(JSON.parse(String(call?.[1]?.body))).toEqual({
    email: "new.owner@example.test",
    current_password: "an example passphrase",
  });
  expect(await screen.findByText("Account updated.")).toBeVisible();
});

test("account password changes explain the revoked session and redirect to sign in", async () => {
  window.history.replaceState({}, "", "/account");
  const fetchImpl = sessionFetch();
  fetchImpl.mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles")
      return response({ roles: [superadminRole, adminRole, memberRole] });
    if (path === "/admin/api/account" && init?.method === "PATCH") {
      expect(JSON.parse(String(init.body))).toEqual({
        email: "owner@example.test",
        current_password: "an example passphrase",
        password: "a brand new passphrase here",
        password_confirmation: "a brand new passphrase here",
      });
      return response({ user: owner });
    }
    if (path === "/auth/api/status") return response({ status: "complete" });
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByRole("heading", { name: "Your account" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Current password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.click(screen.getByRole("checkbox", { name: "Change password" }));
  fireEvent.change(screen.getByLabelText("New password"), {
    target: { value: "a brand new passphrase here" },
  });
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "a brand new passphrase here" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

  await waitFor(() => expect(window.location.pathname).toBe("/auth/login"));
  expect(await screen.findByRole("heading", { name: "Sign in to Vxpipe" })).toBeVisible();
  expect(await screen.findByText(/sessions were signed out/i)).toBeVisible();
  cleanup();
});

test("stale access sessions expire to the login page", async () => {
  window.history.replaceState({}, "", "/account");
  const expired = vi.fn();
  render(
    <App
      csrfToken="csrf-token"
      fetchImpl={() => response({ error: { code: "session_required" } }, 401)}
      onSessionExpired={expired}
    />,
  );
  await waitFor(() => expect(expired).toHaveBeenCalledOnce());
});

test("user creation sends password confirmation, role and tenant mapping", async () => {
  window.history.replaceState({}, "", "/users/new");
  const fetchImpl = sessionFetch();
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByRole("heading", { name: "Create user" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Email"), {
    target: { value: "new.user@example.test" },
  });
  fireEvent.change(screen.getByLabelText("Password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Add tenants" }));
  fireEvent.click(screen.getByRole("checkbox", { name: /Acme/ }));
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fetchImpl.mockImplementationOnce((input: RequestInfo | URL, init?: RequestInit) => {
    expect(String(input)).toBe("/admin/api/users");
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual({
      email: "new.user@example.test",
      password: "an example passphrase",
      password_confirmation: "an example passphrase",
      role_id: "role-member",
      memberships: [{ tenant_id: "acme_demo_000001", access: "read" }],
    });
    return response(
      {
        user: {
          id: "user-9",
          email: "new.user@example.test",
          roleId: "role-member",
          enabled: true,
          memberships: [{ tenantId: "acme_demo_000001", access: "read" }],
        },
      },
      201,
    );
  });
  fireEvent.click(screen.getByRole("button", { name: "Create user" }));

  await waitFor(() =>
    expect(window.location.pathname).toBe("/users/user-9"),
  );
});

test("an Admin sees privileged user details read-only with a working back link", async () => {
  window.history.replaceState({}, "", "/users/user-1");
  const fetchImpl = sessionFetch(adminRole, {
    ...owner,
    id: "user-3",
    email: "admin@example.test",
    roleId: "role-admin",
  });
  fetchImpl.mockImplementation((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session")
      return response({
        user: { ...owner, id: "user-3", email: "admin@example.test", roleId: "role-admin" },
        role: adminRole,
      });
    if (path === "/admin/api/roles")
      return response({ roles: [superadminRole, adminRole, memberRole] });
    if (path === "/admin/api/users/user-1") return response({ user: owner });
    if (path.startsWith("/admin/api/tenants")) return response(tenantDirectory);
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("This account is read-only for your role.")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Save changes" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Reset password" })).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Back to users" })).toHaveAttribute(
    "href",
    "/users",
  );
});

test("superadmin edits save through PATCH and the reset route posts a replacement", async () => {
  window.history.replaceState({}, "", "/users/user-2");
  const fetchImpl = sessionFetch();
  fetchImpl.mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles")
      return response({ roles: [superadminRole, adminRole, memberRole] });
    if (path === "/admin/api/users/user-2") {
      if (init?.method === "PATCH") {
        expect(JSON.parse(String(init.body))).toMatchObject({ email: "member@example.test" });
        return response({ user: member });
      }
      return response({ user: member });
    }
    if (path.startsWith("/admin/api/tenants")) return response(tenantDirectory);
    if (path === "/admin/api/users/user-2/reset-password") return noContent();
    return response({}, 404);
  });
  const view = render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByRole("heading", { name: "User details" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Reset password" })).toHaveAttribute(
    "href",
    "/users/user-2/reset-password",
  );
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() =>
    expect(fetchImpl).toHaveBeenCalledWith(
      "/admin/api/users/user-2",
      expect.objectContaining({ method: "PATCH" }),
    ),
  );

  view.unmount();
  cleanup();
  window.history.replaceState({}, "", "/users/user-2/reset-password");
  const resetFetch = fetchImpl;
  render(<App csrfToken="csrf-token" fetchImpl={resetFetch} />);
  expect(await screen.findByRole("heading", { name: "Reset password" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("New password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "a different passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Set password" }));
  expect(screen.getByRole("alert")).toHaveTextContent("Passwords do not match");
  expect(resetFetch).not.toHaveBeenCalledWith(
    "/admin/api/users/user-2/reset-password",
    expect.anything(),
  );
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Set password" }));
  await waitFor(() =>
    expect(resetFetch).toHaveBeenCalledWith(
      "/admin/api/users/user-2/reset-password",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
      }),
    ),
  );
});

test("roles list links to details and creation navigates to the new role", async () => {  window.history.replaceState({}, "", "/roles");
  const fetchImpl = sessionFetch();
  fetchImpl.mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles") {
      if (init?.method === "POST") {
        expect(JSON.parse(String(init.body))).toMatchObject({ name: "Support" });
        return response(
          { role: { ...memberRole, id: "role-new", name: "Support", revision: 1 } },
          201,
        );
      }
      return response({ roles: [superadminRole, adminRole, memberRole] });
    }
    if (path.startsWith("/admin/api/roles/")) {
      const id = path.split("/").pop();
      const role = [superadminRole, adminRole, memberRole].find((entry) => entry.id === id) ?? memberRole;
      return response({ role, affected_users: 1 });
    }
    if (path.startsWith("/admin/api/users")) return response(userPage([owner, member]));
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText(/Define what people can do/)).toBeVisible();
  expect(screen.getByRole("link", { name: /Tenant Member/ })).toHaveAttribute(
    "href",
    "/roles/role-member",
  );
  fireEvent.click(screen.getByRole("button", { name: "Create role" }));
  expect(await screen.findByRole("heading", { name: "Create role" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Role name"), { target: { value: "Support" } });
  fireEvent.click(screen.getByRole("button", { name: "Create role" }));
  await waitFor(() =>
    expect(window.location.pathname).toBe("/roles/role-new"),
  );
  cleanup();
});

test("roles list shows authoritative affected-user counts without paging the directory", async () => {
  window.history.replaceState({}, "", "/roles");
  const requestedUsers = vi.fn();
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles" && (!init?.method || init.method === "GET"))
      return response({ roles: [superadminRole, memberRole] });
    if (path === "/admin/api/roles/role-super") return response({ role: superadminRole, affected_users: 7 });
    if (path === "/admin/api/roles/role-member") return response({ role: memberRole, affected_users: 0 });
    if (path.startsWith("/admin/api/users")) {
      requestedUsers();
      return response(userPage([]));
    }
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText(/Define what people can do/)).toBeVisible();
  expect(await screen.findByText("Users: 7")).toBeVisible();
  expect(await screen.findByText("Users: 0")).toBeVisible();
  expect(requestedUsers).not.toHaveBeenCalled();
  cleanup();
});

test("role updates send the server revision and stale edits ask for a reload", async () => {
  window.history.replaceState({}, "", "/roles/role-member");
  const detailFetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles/role-member") {
      if (init?.method === "PATCH") {
        const body = JSON.parse(String(init.body));
        expect(body.expected_revision).toBe(2);
        return response({ error: { code: "stale" } }, 409);
      }
      return response({ role: memberRole, affected_users: 3 });
    }
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={detailFetch} />);
  expect(await screen.findByText(/Saving affects 3 users/)).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Save role" }));
  expect(await screen.findByRole("alert")).toHaveTextContent(/changed elsewhere|Reload/);
  cleanup();
});

test("role deletion confirms before sending DELETE and returns to the list", async () => {
  window.history.replaceState({}, "", "/roles/role-member");
  const detailFetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles/role-member") {
      if (init?.method === "DELETE") return noContent();
      return response({ role: memberRole, affected_users: 0 });
    }
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={detailFetch} />);
  expect(await screen.findByRole("button", { name: "Delete role" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Delete role" }));
  fireEvent.click(screen.getByRole("button", { name: "Confirm delete" }));
  await waitFor(() =>
    expect(detailFetch).toHaveBeenCalledWith(
      "/admin/api/roles/role-member",
      expect.objectContaining({ method: "DELETE" }),
    ),
  );
  await waitFor(() => expect(window.location.pathname).toBe("/roles"));
});

test("sign out posts to the logout endpoint with CSRF before leaving", async () => {
  window.history.replaceState({}, "", "/users");
  const fetchImpl = sessionFetch();
  const originalLocation = window.location;
  const assign = vi.fn();
  Object.defineProperty(window, "location", {
    value: { ...originalLocation, assign },
    configurable: true,
  });
  try {
    render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

    expect(await screen.findByText(/Manage who can access/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Logout" }));
    await waitFor(() =>
      expect(fetchImpl).toHaveBeenCalledWith(
        "/auth/logout",
        expect.objectContaining({
          method: "POST",
          headers: expect.objectContaining({ "x-csrf-token": "csrf-token" }),
        }),
      ),
    );
    await waitFor(() => expect(assign).toHaveBeenCalledWith("/auth/login"));
  } finally {
    Object.defineProperty(window, "location", { value: originalLocation, configurable: true });
  }
});

test("failed sign-out keeps the user on the page and explains the failure", async () => {
  window.history.replaceState({}, "", "/users");
  const ordinaryFetch = sessionFetch();
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) =>
    String(input) === "/auth/logout"
      ? response({ error: { code: "unavailable" } }, 503)
      : ordinaryFetch(input, init),
  );
  const originalLocation = window.location;
  const assign = vi.fn();
  Object.defineProperty(window, "location", {
    value: { ...originalLocation, assign },
    configurable: true,
  });
  try {
    render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);
    expect(await screen.findByText(/Manage who can access/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Logout" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(/Logout failed/);
    expect(assign).not.toHaveBeenCalled();
  } finally {
    Object.defineProperty(window, "location", { value: originalLocation, configurable: true });
  }
});

test("users.read-only viewers keep directory filters through the role-options endpoint", async () => {
  window.history.replaceState({}, "", "/users");
  const readerRole = {
    id: "role-reader",
    name: "Custom directory access",
    description: "",
    kind: null,
    grants: [{ permission: "users.read", scope: "installation" }],
    revision: 1,
  };
  const reader = { ...member, id: "user-7", email: "reader@example.test", roleId: "role-reader", memberships: [] };
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: reader, role: readerRole });
    if (path === "/admin/api/roles") return response({ error: { code: "forbidden" } }, 403);
    if (path === "/admin/api/role-options")
      return response({
        roles: [
          { id: "role-super", name: "Superadmin", kind: "superadmin" },
          { id: "role-reader", name: "Custom directory access", kind: null },
        ],
      });
    if (path.startsWith("/admin/api/users")) return response(userPage([reader]));
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText(/Manage who can access/)).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/role-options", expect.any(Object));
  expect(await screen.findByRole("option", { name: "Superadmin" })).toBeVisible();
  expect(await screen.findByRole("table", { name: "Users" })).toBeVisible();
  expect(document.querySelector("a.access-user-link")).toHaveAttribute(
    "href",
    "/users/user-7",
  );
  expect(screen.getAllByText("reader@example.test")[0]).toBeVisible();
  expect(screen.queryByRole("button", { name: "Create user" })).not.toBeInTheDocument();
});

test("unknown role filters keep the URL and explain the empty directory", async () => {
  window.history.replaceState({}, "", "/users?role=no-such-role");
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role: superadminRole });
    if (path === "/admin/api/roles")
      return response({ roles: [superadminRole, adminRole, memberRole] });
    if (path.startsWith("/admin/api/users"))
      return response({ error: { code: "unknown_role" } }, 422);
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Unknown role filter")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe("/users?role=no-such-role");
});

const readMemberRole = {
  id: "role-member",
  name: "Tenant Member",
  description: "",
  kind: null,
  grants: [
    { permission: "calls.read", scope: "assigned_tenants" },
    { permission: "call_specs.read", scope: "assigned_tenants" },
  ],
  revision: 2,
};

test("read-only members get a capability-derived workspace without creation controls", async () => {
  window.history.replaceState({}, "", "/admin/tenants/acme_demo_000001/call-specs");
  const reader = {
    ...member,
    roleId: "role-member",
    memberships: [{ tenantId: "acme_demo_000001", access: "read" }],
  };
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: reader, role: readMemberRole });
    if (path.startsWith("/admin/api/tenants/acme_demo_000001/call-specs"))
      return response({
        tenant: { key: "acme_demo_000001", name: "Acme" },
        call_specs: [],
        pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
      });
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("No call specs yet")).toBeVisible();
  expect(screen.queryByRole("link", { name: "New call spec" })).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Calls" })).toHaveAttribute(
    "href",
    "/t/acme_demo_000001/calls",
  );
  expect(screen.queryByRole("link", { name: "Services" })).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "My account" })).toHaveAttribute(
    "href",
    "/account",
  );
  expect(screen.queryByRole("link", { name: "Users" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Roles" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Services" })).not.toBeInTheDocument();
  cleanup();
});

test("zero-assignment members stay on the directory instead of forbidden onboarding", async () => {
  window.history.replaceState({}, "", "/admin");
  const unassigned = { ...member, memberships: [] };
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: unassigned, role: memberRole });
    if (path.startsWith("/admin/api/tenants?"))
      return response({
        tenants: [],
        pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
      });
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("No tenants available")).toBeVisible();
  expect(window.location.pathname).toBe("/my-tenants");
  cleanup();
});

test("sidebar exposes account and platform links matching authority", async () => {
  window.history.replaceState({}, "", "/admin");
  const adminUser = { ...owner, id: "user-3", email: "admin@example.test", roleId: "role-admin" };
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: adminUser, role: adminRole });
    if (path.startsWith("/admin/api/tenants?")) return response(tenantDirectory);
    return response({}, 404);
  });
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("link", { name: "My account" })).toHaveAttribute("href", "/account");
  expect(screen.getByRole("link", { name: "Users" })).toHaveAttribute("href", "/users");
  expect(screen.getByRole("link", { name: "Roles" })).toHaveAttribute("href", "/roles");
  expect(screen.getByRole("link", { name: "Services" })).toHaveAttribute(
    "href",
    "/platform/services",
  );
  cleanup();
});
