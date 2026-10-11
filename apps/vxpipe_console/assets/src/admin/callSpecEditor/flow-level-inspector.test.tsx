import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowLevelInspector } from "./flow-level-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
afterEach(cleanup);
test("Call settings retains the copied tab layout with five source-backed panels and direction in its header", () => {
  render(<FlowLevelInspector document={editorFixture} onChange={vi.fn()} catalog={modelCatalogFixture} />);
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Models", "Variables", "Media", "Wait sounds", "Advanced"]);
  expect(screen.getByText("Incoming call")).toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "Handled by" })).not.toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: "Call spec name" })).not.toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Variables" }), { button: 0 });
  expect(screen.getByRole("button", { name: "Add section" })).toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: "Call spec name" })).not.toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Models" }), { button: 0 });
  expect(screen.getByRole("region", { name: "Text to speech" })).toBeInTheDocument();
});

test("outgoing call direction is a read-only header label", () => {
  const document = structuredClone(editorFixture);
  delete document.source.incoming_call;
  document.source.outgoing_call = { callee: "caller", handled_by: "intake" };
  render(<FlowLevelInspector document={document} onChange={vi.fn()} catalog={modelCatalogFixture} />);
  expect(screen.getByText("Outgoing call")).toBeInTheDocument();
  expect(screen.queryByRole("tab", { name: "Direction" })).not.toBeInTheDocument();
});
