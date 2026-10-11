import { useState } from "react";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { VoiceField } from "./voice-field";
import type { VoiceCatalogClient, VoiceCatalogPage } from "../voiceCatalog";

afterEach(cleanup);
const skylar = { id: "voice-1", name: "Skylar", attributes: [{ key: "language", label: "Language", value: "English" }] };
const river = { id: "voice-2", name: "River", attributes: [] };
const descriptor = { providerName: "Test audio", modelName: "Speech model", search: true, filters: [
  { key: "language", label: "Language", type: "select" as const, options: [{ value: "en", label: "English" }, { value: "hi", label: "Hindi" }] },
] };
function client(overrides: Partial<VoiceCatalogClient> = {}): VoiceCatalogClient {
  return { describe: vi.fn(async () => descriptor), get: vi.fn(async () => skylar),
    list: vi.fn(async () => ({ voices: [skylar, river], nextCursor: null })), ...overrides };
}
function Harness({ catalog, initial = "voice-1", disabled = false }: { catalog: VoiceCatalogClient; initial?: string; disabled?: boolean }) {
  const [value, onChange] = useState(initial);
  return <><VoiceField client={catalog} provider="test" model="speech" capability="text_to_speech" value={value} onChange={onChange}
    path={["defaults", "capabilities", "text_to_speech", "options", "voice"]} disabled={disabled} /><output data-testid="value">{value}</output></>;
}
async function open() { const trigger = await screen.findByRole("button", { name: /Voice: Skylar/ }); trigger.focus(); fireEvent.click(trigger); await screen.findByRole("radio", { name: /River/ }); }

test("readable voice field opens a picker; selection is staged until Use voice and stores only the ID", async () => {
  render(<Harness catalog={client()} />); await open();
  fireEvent.click(screen.getByRole("radio", { name: /River/ }));
  expect(screen.getByTestId("value")).toHaveTextContent("voice-1");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.getByTestId("value")).toHaveTextContent("voice-1");
  await waitFor(() => expect(screen.getByRole("button", { name: /Voice: Skylar/ })).toHaveFocus());
  await open(); fireEvent.click(screen.getByRole("radio", { name: /River/ }));
  fireEvent.click(screen.getByRole("button", { name: "Use voice" }));
  expect(screen.getByTestId("value")).toHaveTextContent("voice-2");
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("search and provider filters are staged until Apply filters, then request a new first page", async () => {
  const catalog = client({ list: vi.fn(async (_scope, query) => ({ voices: query.cursor ? [river] : [skylar], nextCursor: query.cursor ? null : "page-2" })) });
  render(<Harness catalog={catalog} />);
  fireEvent.click(await screen.findByRole("button", { name: /Voice: Skylar/ }));
  fireEvent.click(await screen.findByRole("button", { name: "Load more voices" }));
  await screen.findByRole("radio", { name: /River/ });
  fireEvent.change(screen.getByRole("searchbox", { name: "Search voices" }), { target: { value: "bright" } });
  expect(catalog.list).toHaveBeenCalledTimes(2);
  expect(screen.getByRole("status")).toHaveTextContent("Unapplied changes");
  fireEvent.click(screen.getByRole("button", { name: "Filters" }));
  fireEvent.click(screen.getByRole("combobox", { name: "Language" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Search language" }), { target: { value: "hind" } });
  expect(screen.queryByRole("option", { name: "English" })).not.toBeInTheDocument();
  fireEvent.click(await screen.findByRole("option", { name: "Hindi" }));
  expect(catalog.list).toHaveBeenCalledTimes(2);
  fireEvent.click(screen.getByRole("button", { name: "Apply filters" }));
  await waitFor(() => expect(catalog.list).toHaveBeenLastCalledWith(expect.anything(), { search: "bright", filters: { language: "hi" }, cursor: null }, expect.any(AbortSignal)));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Results updated"));
  expect(screen.queryByRole("radio", { name: /River/ })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "Accent" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Clear filters and search" }));
  expect(catalog.list).toHaveBeenCalledTimes(3);
  fireEvent.click(screen.getByRole("button", { name: "Apply filters" }));
  await waitFor(() => expect(catalog.list).toHaveBeenLastCalledWith(expect.anything(), { search: "", filters: {}, cursor: null }, expect.any(AbortSignal)));
});

test("the searchable dropdown preserves provider support for multiple languages", async () => {
  const catalog = client({ describe: vi.fn(async () => ({ ...descriptor, filters: [{ ...descriptor.filters[0], type: "multi_select" as const }] })) });
  render(<Harness catalog={catalog} />); await open();
  fireEvent.click(screen.getByRole("button", { name: "Filters" }));
  fireEvent.click(screen.getByRole("combobox", { name: "Language" }));
  fireEvent.click(screen.getByRole("option", { name: "English" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Search language" }), { target: { value: "hind" } });
  fireEvent.click(screen.getByRole("option", { name: "Hindi" }));
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  expect(screen.getByRole("combobox", { name: "Language" })).toHaveTextContent("English, Hindi");
  expect(catalog.list).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: "Apply filters" }));
  await waitFor(() => expect(catalog.list).toHaveBeenLastCalledWith(expect.anything(), { search: "", filters: { language: ["en", "hi"] }, cursor: null }, expect.any(AbortSignal)));
});

test("late results from a previous search cannot replace the current results", async () => {
  let finishOld!: (page: VoiceCatalogPage) => void;
  const catalog = client({ list: vi.fn(async (_scope, query) => query.search === "old" ? new Promise<VoiceCatalogPage>(resolve => { finishOld = resolve; }) : { voices: [river], nextCursor: null }) });
  render(<Harness catalog={catalog} />); await open();
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "old" } });
  fireEvent.click(screen.getByRole("button", { name: "Apply filters" }));
  await waitFor(() => expect(finishOld).toBeDefined());
  expect(screen.getByRole("status")).toHaveTextContent("Updating voices");
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "new" } });
  fireEvent.click(screen.getByRole("button", { name: "Apply filters" }));
  await screen.findByRole("radio", { name: /River/ });
  finishOld({ voices: [skylar], nextCursor: null });
  await waitFor(() => expect(screen.queryByRole("radio", { name: /Skylar/ })).not.toBeInTheDocument());
});

test("unavailable saved voices are kept, request errors can retry, and readonly fields cannot open", async () => {
  const catalog = client({ get: vi.fn(async () => null), list: vi.fn().mockRejectedValueOnce(new Error("private upstream details")).mockResolvedValue({ voices: [river], nextCursor: null }) });
  const view = render(<Harness catalog={catalog} initial="private-voice" />);
  fireEvent.click(await screen.findByRole("button", { name: /Voice: private-voice/ }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Couldn’t load voices");
  expect(screen.queryByText("private upstream details")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await screen.findByRole("radio", { name: /River/ });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.getByTestId("value")).toHaveTextContent("private-voice");
  view.unmount(); render(<Harness catalog={client()} disabled />);
  expect(await screen.findByRole("button", { name: /Voice: Skylar/ })).toBeDisabled();
});
