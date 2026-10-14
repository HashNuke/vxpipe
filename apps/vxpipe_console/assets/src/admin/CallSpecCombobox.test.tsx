import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CallSpecCombobox } from "./CallSpecCombobox";
afterEach(cleanup);

test("searches the remote directory and loads subsequent pages", async () => {
  const search = vi.fn(async (query: string, page: number) => ({
    options: [{ id: `${page}`, name: query ? `Result ${page}` : "Initial" }], hasMore: page === 1,
  }));
  const select = vi.fn();
  render(<CallSpecCombobox options={[]} selectedId={null} unknownSelection={false} search={search} onSelect={select} />);
  fireEvent.click(screen.getByRole("combobox"));
  expect(await screen.findByRole("option", { name: "Initial" })).toBeVisible();
  fireEvent.change(screen.getByPlaceholderText("Search call specs…"), { target: { value: "intake" } });
  expect(await screen.findByRole("option", { name: "Result 1" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Load more" }));
  expect(await screen.findByRole("option", { name: "Result 2" })).toBeVisible();
  expect(screen.getByRole("option", { name: "Result 1" })).toBeVisible();
  fireEvent.click(screen.getByRole("option", { name: "Result 2" }));
  expect(select).toHaveBeenCalledWith("2");
  await waitFor(() => expect(search).toHaveBeenLastCalledWith("intake", 2, expect.any(AbortSignal)));
});

test("ignores stale searches and distinguishes errors from no matches", async () => {
  let resolveOld: ((value: { options: { id: string; name: string }[]; hasMore: boolean }) => void) | undefined;
  const search = vi.fn((query: string) => query === "" ? new Promise<{ options: { id: string; name: string }[]; hasMore: boolean }>((resolve) => { resolveOld = resolve; }) : query === "broken" ? Promise.reject(new Error("offline")) : Promise.resolve({ options: [], hasMore: false }));
  render(<CallSpecCombobox options={[]} selectedId={null} unknownSelection={false} search={search} />);
  fireEvent.click(screen.getByRole("combobox"));
  await waitFor(() => expect(resolveOld).toBeDefined());
  fireEvent.change(screen.getByPlaceholderText("Search call specs…"), { target: { value: "missing" } });
  expect(await screen.findByText("No call specs found.")).toBeVisible();
  resolveOld?.({ options: [{ id: "stale", name: "Stale" }], hasMore: false });
  expect(screen.queryByRole("option", { name: "Stale" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByPlaceholderText("Search call specs…"), { target: { value: "broken" } });
  expect(await screen.findByRole("alert")).toHaveTextContent("Call specs could not be loaded.");
  expect(screen.queryByText("No call specs found.")).not.toBeInTheDocument();
});
