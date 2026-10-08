import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { editorFixture } from "./editorFixtures";
import { Inspector } from "./inspector";

afterEach(cleanup);
const props = { document: editorFixture, onChange: vi.fn(), catalog: modelCatalogFixture,
  lookups: { telephonyServices: [], credentialNames: {}, mcpIntegrations: [] }, onDeleteEdge: vi.fn(), onTabChange: vi.fn(), onRenamed: vi.fn(), onRemoved: vi.fn() };

test("selection routes to call settings, entry, agent and human inspectors", () => {
  const view = render(<Inspector {...props} />);
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toBeInTheDocument();
  view.rerender(<Inspector {...props} selectedNodeId="$entry" />);
  expect(screen.getByText("Entry · Caller")).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Delete participant" })).not.toBeInTheDocument();
  view.rerender(<Inspector {...props} selectedNodeId="intake" />);
  expect(screen.getByRole("textbox", { name: "Prompt" })).toBeInTheDocument();
  view.rerender(<Inspector {...props} selectedNodeId="specialist" />);
  expect(screen.getByRole("textbox", { name: "Private briefing" })).toBeInTheDocument();
});

test("selected transfers expose their endpoints and deletion of that exact edge", () => {
  const onDeleteEdge = vi.fn();
  render(<Inspector {...props} selectedNodeId="intake" selectedEdgeId="transfer:intake:specialist" onDeleteEdge={onDeleteEdge} />);
  expect(screen.getByText("Source").nextElementSibling).toHaveTextContent("intake");
  expect(screen.getByText("Target").nextElementSibling).toHaveTextContent("specialist");
  fireEvent.click(screen.getByRole("button", { name: "Delete transfer" }));
  expect(onDeleteEdge).toHaveBeenCalledWith({ id: "transfer:intake:specialist", source: "intake", target: "specialist", locked: false });
});

test("the entry edge is locked and historical transfers cannot be deleted", () => {
  const view = render(<Inspector {...props} selectedEdgeId="$entry-edge" />);
  expect(screen.getByText("Change the call handler in Call settings.")).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Delete transfer" })).not.toBeInTheDocument();
  view.rerender(<Inspector {...props} document={{ ...editorFixture, readOnly: true }} selectedEdgeId="transfer:intake:specialist" />);
  expect(screen.getByRole("button", { name: "Delete transfer" })).toBeDisabled();
});

test("issue navigation chooses the requested tab without persisting it in source", () => {
  render(<Inspector {...props} selectedNodeId="intake" tab="tools" />);
  expect(screen.getByRole("tab", { name: "Tools" })).toHaveAttribute("data-state", "active");
  expect(screen.getByRole("button", { name: "Add tool" })).toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Transfers" }), { button: 0 });
  expect(props.onTabChange).toHaveBeenCalledWith("transfers");
  expect(props.onChange).not.toHaveBeenCalled();
});

test("a removed selection has a safe summary without edit or delete controls", () => {
  render(<Inspector {...props} selectedNodeId="removed" />);
  expect(screen.getByText("This participant is no longer in the call spec. Select another participant or Call settings.")).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Delete participant" })).not.toBeInTheDocument();
});
