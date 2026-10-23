import { expect, test, vi } from "vitest";
import { AccessKeysApi } from "./accessKeysApi";

test("key administration uses canonical session routes with scoped filters and CSRF writes", async () => {
  const key = { id: "key-id", name: "Backend", kind: "calls", last_four: "abcd", tenant: { key: "TENANT", name: "Acme" }, created_at: "2026-10-15T00:00:00Z", can_revoke: true };
  const fetcher = vi.fn()
    .mockResolvedValueOnce(Response.json({ keys: [key], creatable_kinds: ["calls"], pagination: { page: 2, has_next: false } }))
    .mockResolvedValueOnce(Response.json({ tenants: [key.tenant], pagination: { has_next: false } }))
    .mockResolvedValueOnce(Response.json({ key, secret: "synthetic-once" }, { status: 201 }))
    .mockResolvedValueOnce(new Response(null, { status: 204 }));
  const api = new AccessKeysApi("synthetic-csrf", fetcher);
  const signal = new AbortController().signal;
  expect((await api.list("100% & _", 2, signal)).keys[0].lastFour).toBe("abcd");
  await api.tenants("calls", "Acme", 1, signal);
  expect((await api.create("Backend", "calls", "TENANT")).secret).toBe("synthetic-once");
  await api.revoke("key/id");
  expect(fetcher.mock.calls.map(([url]) => url)).toEqual([
    "/api/api-keys?q=100%25+%26+_&page=2", "/api/api-keys/tenants?kind=calls&q=Acme&page=1",
    "/api/api-keys", "/api/api-keys/key%2Fid",
  ]);
  expect(fetcher.mock.calls[0][1]).toMatchObject({ signal, credentials: "same-origin", cache: "no-store" });
  expect(fetcher.mock.calls[2][1]).toMatchObject({ method: "POST", credentials: "same-origin",
    headers: { "x-csrf-token": "synthetic-csrf" }, body: JSON.stringify({ name: "Backend", kind: "calls", tenant_key: "TENANT" }) });
  expect(fetcher.mock.calls[3][1]).toMatchObject({ method: "DELETE", headers: { "x-csrf-token": "synthetic-csrf" } });
});
