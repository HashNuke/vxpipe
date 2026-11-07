import { afterEach, expect, test } from "vitest";
import { saveOAuthDraft, takeOAuthDraft } from "./oauthDraft";

afterEach(() => sessionStorage.clear());
const identity = { actorId: "actor", tenantKey: "tenant-a", attemptId: "attempt" };
const input = { ...identity, connectionId: "connection", returnTo: "/t/tenant-a/services/search?q=calendar", draft: {
  endpoint: "https://mcp.example.test/mcp", method: "own_client" as const, issuer: "https://auth.example.test", clientAuth: "client_secret_basic" as const,
} };

test("stores only the nonsecret recovery fields and consumes a matching draft once", () => {
  expect(saveOAuthDraft({ ...input, draft: { ...input.draft, clientSecret: "never-store", privateKey: "never-store", tokenParams: [{ name: "token", value: "never-store" }] } }, 1000)).toBe(true);
  expect(sessionStorage.getItem("vxpipe.mcp.oauth")).not.toContain("never-store");
  expect(takeOAuthDraft(identity, 2000)).toEqual({ ...input, createdAt: 1000 });
  expect(takeOAuthDraft(identity, 2001)).toBeNull();
});

test("listed retry context keeps its public reference and cannot restore as a custom endpoint", () => {
  const listing = { reference: { directory_id: "directory", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant" } },
    entry: { directory_id: "directory", integration_id: "calendar", revision: 1, name: "Calendar", endpoint: input.draft.endpoint,
      authentication: { type: "oauth2", registration: "preregistered" } } };
  expect(saveOAuthDraft({ ...input, draft: { ...input.draft, listing } }, 1000)).toBe(true);
  expect(takeOAuthDraft(identity, 2000)?.draft).toEqual({ ...input.draft, listing });
  expect(saveOAuthDraft({ ...input, draft: { ...input.draft, listing: { ...listing, entry: { ...listing.entry, endpoint: "https://other.test/mcp" } } } }, 1000)).toBe(false);
  sessionStorage.setItem("vxpipe.mcp.oauth", JSON.stringify({ ...input, createdAt: 1000, draft: { ...input.draft, listing: { reference: {}, entry: {} } } }));
  expect(takeOAuthDraft(identity, 2000)).toBeNull();
  expect(sessionStorage.getItem("vxpipe.mcp.oauth")).toBeNull();
});

test("requires the same actor, tenant and attempt and expires after five minutes", () => {
  saveOAuthDraft(input, 1000);
  for (const mismatch of [{ actorId: "other" }, { tenantKey: "other" }, { attemptId: "other" }]) expect(takeOAuthDraft({ ...identity, ...mismatch }, 2000)).toBeNull();
  expect(takeOAuthDraft(identity, 301001)).toBeNull();
  expect(sessionStorage.getItem("vxpipe.mcp.oauth")).toBeNull();
});

test("does not persist URL query values or foreign return paths", () => {
  expect(saveOAuthDraft({ ...input, draft: { ...input.draft, endpoint: "https://mcp.example.test/mcp?key=secret" } }, 1000)).toBe(false);
  expect(saveOAuthDraft({ ...input, returnTo: "/t/other/services" }, 1000)).toBe(false);
  expect(sessionStorage.length).toBe(0);
});

test("unavailable storage and corrupted records cannot prevent navigation or restore a draft", () => {
  const unavailable = { setItem() { throw new Error("disabled"); }, getItem() { throw new Error("disabled"); }, removeItem() { throw new Error("disabled"); } };
  expect(saveOAuthDraft(input, 1000, unavailable)).toBe(false);
  expect(takeOAuthDraft(identity, 2000, unavailable)).toBeNull();
  sessionStorage.setItem("vxpipe.mcp.oauth", JSON.stringify({ ...input, createdAt: 1000, draft: { ...input.draft, token: "untrusted" } }));
  expect(takeOAuthDraft(identity, 2000)).toBeNull();
});

test("valid percent-encoded directory queries fit the server return-location contract", () => {
  const returnTo = `/t/tenant-a/services/search?${new URLSearchParams({ q: "日".repeat(100), cursor: "a".repeat(1500) })}`;
  expect(saveOAuthDraft({ ...input, returnTo }, 1000)).toBe(true);
  expect(takeOAuthDraft(identity, 2000)?.returnTo).toBe(returnTo);
});

test("malformed timestamps and control characters cannot be restored", () => {
  sessionStorage.setItem("vxpipe.mcp.oauth", JSON.stringify({ ...input, createdAt: "1000" }));
  expect(takeOAuthDraft(identity, 2000)).toBeNull();
  expect(saveOAuthDraft({ ...input, returnTo: "/t/tenant-a/services?q=%0A" }, 1000)).toBe(false);
});
