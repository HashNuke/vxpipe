import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { IssueScope, UnplacedIssues } from "./issue-scope";
import { TextField } from "./editor-fields";
import type { SourceIssue } from "./types";
afterEach(cleanup);
const issue: SourceIssue = { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "Prompt is required" };
function Fields({ issues = [issue], request, showPrompt = true }: { showPrompt?: boolean; issues?: SourceIssue[]; request?: { id: number; path: string[] } }) {
  return <IssueScope issues={issues} request={request}><UnplacedIssues />{showPrompt && <TextField label="Prompt" path={issue.path} value="" onChange={vi.fn()} />}<TextField label="Other" path={["other"]} value="" onChange={vi.fn()} /></IssueScope>;
}
test("visible fields own their errors without duplicating the summary", () => {
  render(<Fields />);
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveAttribute("aria-invalid", "true");
  expect(screen.getAllByText("Prompt is required")).length(1);
  expect(screen.queryByRole("region", { name: "Other issues in this tab" })).not.toBeInTheDocument();
});
test("Show focuses a field and does not steal focus again on edits", () => {
  const request = { id: 1, path: issue.path };
  const { rerender } = render(<Fields request={request} />);
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveFocus();
  screen.getByRole("textbox", { name: "Other" }).focus();
  rerender(<Fields request={request} issues={[{ ...issue, reason: "New reason" }]} />);
  expect(screen.getByRole("textbox", { name: "Other" })).toHaveFocus();
});
test("collection errors use the nearest editable field and unrepresented errors use the tab summary", () => {
  const parent = { ...issue, path: ["participants", "intake"] };
  const absent = { ...issue, path: ["missing"], reason: "Missing setting" };
  const { rerender } = render(<Fields issues={[parent, absent]} request={{ id: 1, path: parent.path }} />);
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveFocus();
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveAccessibleDescription("Prompt is required");
  expect(screen.getByRole("region", { name: "Other issues in this tab" })).toHaveTextContent("Missing setting");
  rerender(<Fields issues={[parent, absent]} request={{ id: 2, path: absent.path }} />);
  expect(screen.getByRole("region", { name: "Other issues in this tab" })).toHaveFocus();
  fireEvent.change(screen.getByRole("textbox", { name: "Prompt" }), { target: { value: "help" } });
});

test("inspector badges count hidden-tab errors while inline messages follow the open tab", async () => {
  const { FlowLevelInspector } = await import("./flow-level-inspector");
  const { editorFixture } = await import("./editorFixtures");
  const { modelCatalogFixture } = await import("../modelCatalogFixtures");
  const problems = [{ ...issue, path: ["name"], reason: "Choose a name" }, { ...issue, path: ["limits", "max_duration_ms"], reason: "Duration too short" }];
  render(<FlowLevelInspector document={editorFixture} onChange={vi.fn()} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: [] }} issues={problems} />);
  expect(screen.getByRole("tab", { name: "Advanced" })).toHaveAttribute("aria-description", "1 issue");
  expect(screen.getByText("Choose a name")).toBeInTheDocument();
  expect(screen.queryByText("Duration too short")).not.toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Advanced" }), { button: 0 });
  expect(screen.getByText("Duration too short")).toBeInTheDocument();
  expect(screen.queryByText("Choose a name")).not.toBeInTheDocument();
});

test.each([["tool", "Tool name"], ["slots", "Local tool key"]])("Show reveals a tool dialog at its named field: %s", async (field, label) => {
  const { AgentInspector } = await import("./agent-inspector");
  const { editorFixture } = await import("./editorFixtures");
  const { modelCatalogFixture } = await import("../modelCatalogFixtures");
  const document = structuredClone(editorFixture);
  document.source.participants.intake = { type: "agent", prompt: "help", tools: { slots: { type: "mcp", integration: "calendar", tool: "find_slots" } } };
  const problem = { ...issue, path: field === "slots" ? ["participants", "intake", "tools", "slots"] : ["participants", "intake", "tools", "slots", field], reason: "Tool not found" };
  render(<AgentInspector document={document} onChange={vi.fn()} participantKey="intake" tab="tools" catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: ["calendar"] }} issues={[problem]} focusRequest={{ id: 1, path: problem.path }} />);
  expect(await screen.findByRole("dialog", { name: "Edit tool" })).toBeInTheDocument();
  expect(screen.getByRole("textbox", { name: label })).toHaveFocus();
  expect(screen.getByRole("textbox", { name: label })).toHaveAccessibleDescription(expect.stringContaining("Tool not found"));
});
test("Show expands collapsed variable constraints before focusing", async () => {
  const { FlowLevelInspector } = await import("./flow-level-inspector");
  const { editorFixture } = await import("./editorFixtures");
  const { modelCatalogFixture } = await import("../modelCatalogFixtures");
  const document = structuredClone(editorFixture);
  document.source.call_variables = { sections: { contact: { schema: { type: "object", properties: { name: { type: "string" } } } } } };
  const problem = { ...issue, path: ["call_variables", "sections", "contact", "schema", "properties", "name", "minLength"], reason: "Set a minimum length" };
  render(<FlowLevelInspector document={document} onChange={vi.fn()} tab="variables" catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: [] }} issues={[problem]} focusRequest={{ id: 1, path: problem.path }} />);
  expect(await screen.findByRole("spinbutton", { name: "contact / name minLength" })).toHaveFocus();
});

test("removing an already focused field does not replay its old Show request", () => {
  const request = { id: 1, path: issue.path };
  const { rerender } = render(<Fields request={request} />);
  screen.getByRole("textbox", { name: "Other" }).focus();
  rerender(<Fields request={request} showPrompt={false} />);
  expect(screen.getByRole("textbox", { name: "Other" })).toHaveFocus();
});
