import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { EditorPageState } from "./editor-page-state";
afterEach(cleanup);
test("loading shows a page status without authoring actions", () => {
  render(<EditorPageState status="loading" backHref="/specs" onRetry={vi.fn()} />);
  expect(screen.getByRole("status")).toHaveTextContent("Loading call spec editor");
  expect(screen.queryByRole("button", { name: "Save draft" })).not.toBeInTheDocument();
});
test.each(["spec", "catalog"] as const)("a %s load failure offers page retry", (resource) => {
  const retry = vi.fn(); render(<EditorPageState status="error" resource={resource} backHref="/specs" onRetry={retry} />);
  expect(screen.getByRole("heading", { name: resource === "spec" ? "Call spec unavailable" : "Model catalog unavailable" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry" })); expect(retry).toHaveBeenCalledOnce();
  expect(screen.queryByLabelText("Notification")).not.toBeInTheDocument();
});
