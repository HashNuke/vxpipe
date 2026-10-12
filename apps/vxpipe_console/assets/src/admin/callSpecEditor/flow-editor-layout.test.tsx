import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowEditorLayout } from "./flow-editor-layout";
import { editorFixture } from "./editorFixtures";

vi.mock("./flow-canvas", () => ({ FlowCanvas: ({ onSelectNode }: { onSelectNode: (id: string) => void }) => <button onClick={() => onSelectNode("intake")}>Select intake</button> }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

test("shell opens participants and Call settings from the canvas toolbar on phones", () => {
  vi.stubGlobal("innerWidth", 390);
  const select = vi.fn();
  render(<FlowEditorLayout document={editorFixture} backHref="/specs" onEditFlowName={vi.fn()} onSaveDraft={vi.fn()} onPublish={vi.fn()} onShowIssues={vi.fn()}
    onAddNode={vi.fn()} onConnect={vi.fn()} onSelectNode={select} onSelectEdge={vi.fn()} selectedNodeId={null}
    inspector={<p>Inspector content</p>} inspectorTitle="Call settings" />);
  const settings = screen.getByRole("button", { name: "Call settings" });
  expect(document.querySelector("[data-flow-editor-header]")?.contains(screen.getByRole("toolbar"))).toBe(true);
  expect(screen.getByRole("toolbar").contains(settings)).toBe(true);
  expect(settings).not.toHaveTextContent("Call settings");
  fireEvent.click(settings);
  expect(select).toHaveBeenLastCalledWith(null);
  expect(screen.getByRole("dialog", { name: "Call settings" })).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  fireEvent.click(screen.getByRole("button", { name: "Select intake" }));
  expect(select).toHaveBeenCalledWith("intake");
  expect(screen.getByRole("dialog", { name: "Call settings" })).toBeInTheDocument();
});

test("historical source shows its notice and disables authoring", () => {
  render(<FlowEditorLayout document={{ ...editorFixture, readOnly: true, notice: "Historical schema: read only" }} backHref="/specs"
    onEditFlowName={vi.fn()} onSaveDraft={vi.fn()} onPublish={vi.fn()} onShowIssues={vi.fn()} onAddNode={vi.fn()} onConnect={vi.fn()}
    onSelectNode={vi.fn()} onSelectEdge={vi.fn()} selectedNodeId={null} inspector={<p>Inspector content</p>} inspectorTitle="Call settings" />);
  expect(screen.getByText("Historical schema: read only")).toBeVisible();
  expect(screen.getByRole("button", { name: "More actions" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add agent" })).toBeDisabled();
});

test("Call settings carries its issue count and an external Show request opens the phone inspector", () => {
  vi.stubGlobal("innerWidth", 390);
  render(<FlowEditorLayout document={editorFixture} backHref="/specs" onEditFlowName={vi.fn()} onSaveDraft={vi.fn()} onPublish={vi.fn()} onShowIssues={vi.fn()}
    onAddNode={vi.fn()} onConnect={vi.fn()} onSelectNode={vi.fn()} onSelectEdge={vi.fn()} selectedNodeId={null} issues={{ $settings: 2 }} inspectorRequest={1}
    inspector={<p>Inspector content</p>} inspectorTitle="Call settings" />);
  expect(screen.getByRole("dialog", { name: "Call settings" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Call settings", hidden: true })).toHaveAttribute("aria-description", "2 issues");
});
