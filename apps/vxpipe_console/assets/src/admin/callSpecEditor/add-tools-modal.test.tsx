import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { AddToolsModal } from "./add-tools-modal";
import { EditToolModal } from "./edit-tool-modal";
import { editorFixture } from "./editorFixtures";
import type { SourceDocument } from "./types";

const catalog = { mcpAvailable: true, tools: [
  { type: "platform" as const, tool: "hangup", description: "End the call." },
  { type: "mcp" as const, integration: "calendar", tool: "find_slots", description: "Find available times." },
  { type: "mcp" as const, integration: "calendar", tool: "book_slot", description: "Book an appointment." },
] };
afterEach(cleanup);
function Harness({ initial = editorFixture, previousName }: { initial?: SourceDocument; previousName?: string }) {
  const [document, onChange] = useState(initial);
  const [open, setOpen] = useState(true);
  return <>{open && (previousName !== undefined ? <EditToolModal document={document} onChange={onChange} participantKey="intake" name={previousName} onClose={() => setOpen(false)} /> : <AddToolsModal document={document} onChange={onChange} participantKey="intake" integrations={["calendar", "unavailable"]} catalog={catalog} onClose={() => setOpen(false)} />)}
    <output data-testid="source">{JSON.stringify(document.source)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
const click = (name: string) => fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name }));
const search = (name: string, value: string) => fireEvent.change(screen.getByRole("searchbox", { name }), { target: { value } });

test("searchable MCP picker adds checked tools together, retains filtered selections and never asks for keys", () => {
  render(<Harness />);
  expect(screen.queryByLabelText("Local tool key")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Next" })).not.toBeInTheDocument();
  search("Search tools and MCPs", "calendar");
  expect(screen.queryByRole("button", { name: "hangup" })).not.toBeInTheDocument();
  click("calendar");
  fireEvent.click(screen.getByRole("checkbox", { name: "find_slots" }));
  search("Search calendar tools", "book");
  fireEvent.click(screen.getByRole("checkbox", { name: "book_slot" }));
  expect(screen.getByText("2 selected")).toBeVisible();
  click("Add 2 tools");
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(saved().participants.intake.tools).toMatchObject({
    calendar__find_slots: { type: "mcp", integration: "calendar", tool: "find_slots" },
    calendar__book_slot: { type: "mcp", integration: "calendar", tool: "book_slot" },
  });
});
test("built-in selection has inline options, and cancel never changes the document", () => {
  render(<Harness />);
  click("hangup");
  expect(screen.getByRole("combobox", { name: "Conversation mode" })).toBeVisible();
  click("Cancel");
  expect(saved()).toEqual(editorFixture.source);
});
test("editing an unavailable saved tool preserves its alias and visibility", () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake = { type: "agent", prompt: "help", tools: { custom_alias: { type: "mcp", integration: "old", tool: "old_tool" } } };
  initial.source.tool_visibility_overrides = { intake: { custom_alias: "metadata" } };
  render(<Harness initial={initial} previousName="custom_alias" />);
  expect(screen.getByText("old · old_tool")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Change tool" })).not.toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: /key/i })).not.toBeInTheDocument();
  click("Save tool");
  expect(saved()).toEqual(initial.source);
});
test("configured MCPs without a usable catalog show an explicit empty state", () => {
  render(<Harness />);
  click("unavailable");
  expect(screen.getByText(/No tools are available from this MCP/)).toBeVisible();
  expect(screen.getByRole("button", { name: "Add tools" })).toBeDisabled();
});
test("save failures retain checked tools and leave the source unchanged", () => {
  const change = vi.fn(() => { throw new Error("Cannot update this draft"); });
  render(<AddToolsModal document={editorFixture} onChange={change} participantKey="intake" integrations={["calendar"]} catalog={catalog} onClose={vi.fn()} />);
  click("calendar"); fireEvent.click(screen.getByRole("checkbox", { name: "book_slot" })); click("Add 1 tool");
  expect(screen.getByRole("alert")).toHaveTextContent("Cannot update this draft");
  expect(screen.getByRole("checkbox", { name: "book_slot" })).toBeChecked();
});

test("first screen groups built-ins and MCP names without exposing individual MCP tools", () => {
  render(<Harness />);
  expect(within(screen.getByRole("region", { name: "Built-in tools" })).getByRole("button", { name: "hangup" })).toBeVisible();
  expect(within(screen.getByRole("region", { name: "MCP integrations" })).getByRole("button", { name: "calendar" })).toHaveTextContent(/^calendar \(2\)$/);
  expect(screen.getByRole("button", { name: "unavailable" })).toHaveTextContent(/^unavailable \(0\)$/);
  expect(screen.queryByText("find_slots")).not.toBeInTheDocument();
  search("Search tools and MCPs", "find_slots");
  expect(screen.queryByRole("button", { name: "calendar" })).not.toBeInTheDocument();
});
test("include all snapshots explicit tool names across filters and never opts into future tools", () => {
  const onChange = vi.fn();
  const props = { document: editorFixture, onChange, participantKey: "intake", integrations: ["calendar"], catalog, onClose: vi.fn() };
  const view = render(<AddToolsModal {...props} />);
  click("calendar");
  search("Search calendar tools", "book");
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  expect(screen.getByText("2 selected")).toBeVisible();
  expect(screen.getByRole("checkbox", { name: "Include all tools" })).toBeChecked();
  view.rerender(<AddToolsModal {...props} catalog={{ ...catalog, tools: [...catalog.tools, { type: "mcp", integration: "calendar", tool: "delete_calendar", description: "Delete a calendar." }] }} />);
  expect(screen.getByRole("checkbox", { name: "Include all tools" })).toBePartiallyChecked();
  click("Add 2 tools");
  const tools = onChange.mock.calls[0]![0].source.participants.intake.tools;
  expect(Object.keys(tools)).toEqual(["availability", "calendar__find_slots", "calendar__book_slot"]);
  expect(tools.calendar__find_slots).toEqual({ type: "mcp", integration: "calendar", tool: "find_slots" });
  expect(tools.calendar__book_slot).toEqual({ type: "mcp", integration: "calendar", tool: "book_slot" });
  expect(JSON.stringify(tools)).not.toContain("*");
});
test("include all can be cleared while already-enabled tools remain enabled", () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake = { type: "agent", prompt: "help", tools: { calendar__find_slots: { type: "mcp", integration: "calendar", tool: "find_slots" } } };
  render(<Harness initial={initial} />); click("calendar");
  expect(screen.getByRole("checkbox", { name: "Include all tools" })).toBePartiallyChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  expect(screen.getByText("1 selected")).toBeVisible();
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  expect(screen.getByRole("button", { name: "Add tools" })).toBeDisabled();
  expect(screen.getByRole("checkbox", { name: "find_slots" })).toBeChecked();
  expect(saved()).toEqual(initial.source);
});

test("MCP tools configure conversation mode only through each tool's checkbox", () => {
  render(<Harness />); click("calendar");
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "Non-blocking book_slot" }));
  expect(screen.queryByRole("combobox", { name: "Conversation mode" })).not.toBeInTheDocument();
  expect(screen.getByRole("checkbox", { name: "Non-blocking find_slots" })).not.toBeChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Non-blocking find_slots" }));
  expect(screen.getByRole("checkbox", { name: "Non-blocking find_slots" })).toBeChecked();
  expect(screen.getByRole("checkbox", { name: "Non-blocking book_slot" })).toBeChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Non-blocking find_slots" }));
  click("Add 2 tools");
  expect(saved().participants.intake.tools.calendar__find_slots).toEqual({ type: "mcp", integration: "calendar", tool: "find_slots" });
  expect(saved().participants.intake.tools.calendar__book_slot).toEqual({ type: "mcp", integration: "calendar", tool: "book_slot", conversation_mode: "non_blocking" });
});

test("include all can be cleared when a catalog tool has an unavailable registered name", () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake = { type: "agent", prompt: "help", tools: { calendar__find_slots: { type: "mcp", integration: "legacy", tool: "lookup" } } };
  render(<Harness initial={initial} />); click("calendar");
  expect(screen.getByRole("checkbox", { name: "find_slots" })).toBeDisabled();
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  expect(screen.getByRole("checkbox", { name: "Include all tools" })).toBeChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  expect(screen.getByRole("button", { name: "Add tools" })).toBeDisabled();
  expect(saved()).toEqual(initial.source);
});

test("the MCP picker shows remote names only, saves qualified names, and excludes incompatible registrations", () => {
  const onChange = vi.fn();
  const longName = "x".repeat(55);
  render(<AddToolsModal document={editorFixture} onChange={onChange} participantKey="intake" integrations={["calendar"]} catalog={{ ...catalog, tools: [...catalog.tools, { type: "mcp", integration: "calendar", tool: longName, description: "Over the combined name limit" }] }} onClose={vi.fn()} />);
  click("calendar");
  expect(screen.getByRole("checkbox", { name: "find_slots" })).toBeVisible();
  expect(screen.queryByText("calendar__find_slots")).not.toBeInTheDocument();
  expect(screen.getByRole("checkbox", { name: longName })).toBeDisabled();
  expect(screen.getByText("Name exceeds 64 characters")).toBeVisible();
  fireEvent.click(screen.getByRole("checkbox", { name: "Include all tools" }));
  click("Add 2 tools");
  expect(Object.keys(onChange.mock.calls[0]![0].source.participants.intake.tools)).toEqual(["availability", "calendar__find_slots", "calendar__book_slot"]);
});


test("a built-in tool's mode never becomes a default for another tool", async () => {
  render(<Harness />);
  click("hangup");
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Conversation mode" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "Non-blocking" }));
  click("All tools and MCPs");
  click("calendar");
  fireEvent.click(screen.getByRole("checkbox", { name: "find_slots" }));
  expect(screen.getByRole("checkbox", { name: "Non-blocking find_slots" })).not.toBeChecked();
});
