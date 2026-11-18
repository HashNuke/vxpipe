import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { CallSpecStatusBadge } from "./CallSpecStatusBadge";
afterEach(cleanup);

test("list badge uses publication metadata rather than internal save counters", () => {
  const callSpec = { id: "1", name: "Intake", latestRevision: 12, publishedRevision: 9, publishedVersion: 6, unpublishedChanges: false, callCount: 0, updatedAt: "2026-11-17T12:00:00Z" };
  const { rerender } = render(<CallSpecStatusBadge callSpec={callSpec} />);
  expect(screen.getByText("v6 Published")).toBeVisible();
  expect(screen.queryByText(/Unpublished changes/)).not.toBeInTheDocument();
  rerender(<CallSpecStatusBadge callSpec={{ ...callSpec, unpublishedChanges: true }} />);
  expect(screen.getByText("v6 · Unpublished changes")).toBeVisible();
});
