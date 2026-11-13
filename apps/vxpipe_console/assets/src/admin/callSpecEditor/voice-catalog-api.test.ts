import { expect, test, vi } from "vitest";
import type { EditorFetch } from "./editor-api";
import { createVoiceCatalogClient } from "./voice-catalog-api";
const scope = { provider: "elevenlabs", model: "eleven_flash_v2_5", capability: "text_to_speech" as const, credential_name: "office" };
const voice = { id: "voice-2", name: "River", attributes: [] };
test("scopes all requests to the tenant and selected binding without caching or eager requests", async () => {
  const fetch = vi.fn<EditorFetch>(async () => new Response(JSON.stringify({ voices: [voice], nextCursor: "next" })));
  const client = createVoiceCatalogClient("tenant/one", fetch);
  expect(fetch).not.toHaveBeenCalled();
  const signal = new AbortController().signal;
  expect(await client.list(scope, { search: "bright", filters: { language: "en" }, cursor: "page" }, signal)).toEqual({ voices: [voice], nextCursor: "next" });
  const [path, init] = fetch.mock.calls[0]! as unknown as [string, RequestInit];
  const url = new URL(path, "https://console.test");
  expect(url.pathname).toBe("/admin/api/tenants/tenant%2Fone/providers/elevenlabs/voices");
  expect(Object.fromEntries(url.searchParams)).toEqual({ model: scope.model, capability: scope.capability, credential_name: "office", search: "bright", filters: '{"language":"en"}', cursor: "page" });
  expect(init).toMatchObject({ signal, cache: "no-store", credentials: "same-origin" });
  fetch.mockResolvedValueOnce(new Response(JSON.stringify({ voice })));
  expect(await client.get(scope, "voice-2", signal)).toEqual(voice);
  expect(String(fetch.mock.calls.at(-1)?.[0])).toContain("/voices/voice-2?");
});
test("rejects malformed and oversized pages and sanitizes upstream failures", async () => {
  const fetch = vi.fn(); const client = createVoiceCatalogClient("tenant", fetch); const signal = new AbortController().signal;
  for (const body of [{ voices: [{}], nextCursor: null }, { voices: Array(101).fill(voice), nextCursor: null }, { voices: [], nextCursor: {} }]) {
    fetch.mockResolvedValueOnce(new Response(JSON.stringify(body)));
    await expect(client.list(scope, { search: "", filters: {}, cursor: null }, signal)).rejects.toThrow("Invalid voice catalog response");
  }
  fetch.mockResolvedValueOnce(new Response("private upstream body", { status: 403 }));
  await expect(client.get(scope, "saved", signal)).rejects.toThrow("Voice catalog access is unavailable");
  fetch.mockResolvedValueOnce(new Response(JSON.stringify({ voice: null })));
  expect(await client.get(scope, "saved", signal)).toBeNull();
});
