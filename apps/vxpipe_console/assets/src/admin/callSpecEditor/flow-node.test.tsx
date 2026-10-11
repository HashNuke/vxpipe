import { cleanup, render, screen } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import { afterEach, expect, test } from "vitest";
import { FlowNode } from "./flow-node";
import { canvasGraph } from "./flow-layout";
import { editorFixture } from "./editorFixtures";

afterEach(cleanup);

test.each([0, 1, 5])("agent card displays %i variables with a compact name-only heading", (variableCount) => {
  const node = canvasGraph(editorFixture).nodes.find((node) => node.id === "intake")!;
  render(<ReactFlowProvider><FlowNode data={{ ...node.data, variableCount }} /></ReactFlowProvider>);
  expect(screen.getByText("intake")).toBeInTheDocument();
  expect(screen.getByText(`${variableCount} ${variableCount === 1 ? "variable" : "variables"}`)).toHaveAttribute("title", "Variables this agent can write");
  expect(screen.queryByText(/Help the caller/)).not.toBeInTheDocument();
  expect(screen.getByText("1 tool")).toBeInTheDocument();
});
