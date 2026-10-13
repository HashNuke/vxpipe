import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { NavigationApi } from "./navigationApi";
import { useTenantSearch } from "./useTenantSearch";

afterEach(cleanup);
const first = { key: "AAAAAAAAAAAAAAAA", name: "First", createdAt: "2026-10-13T00:00:00Z" };
const second = { key: "BBBBBBBBBBBBBBBB", name: "Second", createdAt: "2026-10-13T00:00:00Z" };
function setup() {
  const api = new NavigationApi();
  const search = vi.spyOn(api, "tenants").mockImplementation(async (_query, page = 1) => ({ tenants: page === 1 ? [first] : [second], pagination: { page, pageSize: 25, total: 26, totalPages: 2 } }));
  const onFailure = vi.fn();
  const hook = renderHook(({ enabled, authority }) => useTenantSearch(api, enabled, onFailure, authority), { initialProps: { enabled: true, authority: 1 } });
  return { ...hook, search };
}
test("reopening a paginated picker restarts at the first authorized page", async () => {
  const { result, rerender, search } = setup();
  await waitFor(() => expect(result.current.tenants).toEqual([first]));
  act(() => result.current.more());
  await waitFor(() => expect(result.current.tenants).toEqual([first, second]));
  rerender({ enabled: false, authority: 1 });
  rerender({ enabled: true, authority: 1 });
  await waitFor(() => expect(result.current.tenants).toEqual([first]));
  expect(search).toHaveBeenLastCalledWith("", 1, expect.any(AbortSignal));
});
test("authority refresh discards cached pages and removed memberships", async () => {
  const { result, rerender, search } = setup();
  await waitFor(() => expect(result.current.tenants).toEqual([first]));
  act(() => result.current.more());
  await waitFor(() => expect(result.current.tenants).toEqual([first, second]));
  search.mockResolvedValue({ tenants: [second], pagination: { page: 1, pageSize: 25, total: 1, totalPages: 1 } });
  rerender({ enabled: true, authority: 2 });
  await waitFor(() => expect(result.current.tenants).toEqual([second]));
  expect(search).toHaveBeenLastCalledWith("", 1, expect.any(AbortSignal));
});
