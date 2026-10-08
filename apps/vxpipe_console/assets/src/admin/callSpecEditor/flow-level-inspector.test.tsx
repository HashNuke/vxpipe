import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowLevelInspector } from "./flow-level-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
afterEach(cleanup);
test("Call settings retains the copied tab layout with all six source-backed panels", () => {
  render(<FlowLevelInspector document={editorFixture} onChange={vi.fn()} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: [] }} />);
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Direction", "Defaults", "Variables", "Media and recording", "Wait sounds", "Advanced"]);
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Variables" }), { button: 0 });
  expect(screen.getByRole("button", { name: "Add section" })).toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: "Call spec name" })).not.toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Defaults" }), { button: 0 });
  expect(screen.getByRole("region", { name: "Text to speech" })).toBeInTheDocument();
});
