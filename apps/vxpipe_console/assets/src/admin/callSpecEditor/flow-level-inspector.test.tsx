import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowLevelInspector } from "./flow-level-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
afterEach(cleanup);
const lookups = { telephonyServices: [] };
test("Call settings starts on Connection and groups wait sounds with call-wide Media", () => {
  render(<FlowLevelInspector document={editorFixture} onChange={vi.fn()} catalog={modelCatalogFixture} lookups={lookups} />);
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Connection", "Models", "Variables", "Media", "Advanced"]);
  expect(screen.getByText("Incoming call")).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Handled by" })).toBeVisible();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Media" }), { button: 0 });
  expect(screen.getByRole("combobox", { name: "Record audio" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Wait sounds" })).toBeVisible();
  expect(screen.getByRole("combobox", { name: "Call setup" })).toBeVisible();
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
  render(<FlowLevelInspector document={document} onChange={vi.fn()} catalog={modelCatalogFixture} lookups={lookups} />);
  expect(screen.getByText("Outgoing call")).toBeInTheDocument();
  expect(screen.queryByRole("tab", { name: "Direction" })).not.toBeInTheDocument();
});

test("Call settings edits the call-wide preference list in priority order", () => {
  const change = vi.fn();
  const document = { ...editorFixture, source: { ...editorFixture.source, conversation_languages: ["en-GB", "es-MX"] } };
  render(<FlowLevelInspector document={document} onChange={change} tab="defaults" catalog={modelCatalogFixture} lookups={lookups} />);
  fireEvent.click(screen.getByRole("button", {name: /Remove British English/}));
  expect(change.mock.lastCall?.[0].source.conversation_languages).toEqual(["es-MX"]);
});
