import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowEditorLayout } from "./flow-editor-layout";
import { editorFixture } from "./editorFixtures";

vi.mock("./flow-canvas", () => ({ FlowCanvas: ({ onSelectNode }: { onSelectNode: (id: string) => void }) => <button onClick={() => onSelectNode("intake")}>Select intake</button> }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

test("shell opens the inspector for a selected participant and exposes Call settings", () => {
  vi.stubGlobal("innerWidth", 390);
  const select = vi.fn();
  render(<FlowEditorLayout document={editorFixture} backHref="/specs" onEditFlowName={vi.fn()} onSaveDraft={vi.fn()} onPublish={vi.fn()} onShowIssues={vi.fn()}
    onAddNode={vi.fn()} onConnect={vi.fn()} onSelectNode={select} onSelectEdge={vi.fn()} selectedNodeId={null}
    inspector={<p>Inspector content</p>} inspectorTitle="Call settings" />);
  fireEvent.click(screen.getByRole("button", { name: "Select intake" }));
  expect(select).toHaveBeenCalledWith("intake");
  expect(screen.getByRole("dialog", { name: "Call settings" })).toBeInTheDocument();
});

test("historical source shows its notice and disables authoring", () => {
  render(<FlowEditorLayout document={{ ...editorFixture, readOnly: true, notice: "Historical schema: read only" }} backHref="/specs"
    onEditFlowName={vi.fn()} onSaveDraft={vi.fn()} onPublish={vi.fn()} onShowIssues={vi.fn()} onAddNode={vi.fn()} onConnect={vi.fn()}
    onSelectNode={vi.fn()} onSelectEdge={vi.fn()} selectedNodeId={null} inspector={<p>Inspector content</p>} inspectorTitle="Call settings" />);
  expect(screen.getByText("Historical schema: read only")).toBeVisible();
  expect(screen.getByRole("button", { name: "Save draft" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add agent" })).toBeDisabled();
});
