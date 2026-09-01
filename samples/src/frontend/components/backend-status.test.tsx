import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { BackendStatus } from "./backend-status";

describe("BackendStatus", () => {
  it("identifies a connected sample backend", () => {
    render(<BackendStatus state="connected" />);

    expect(screen.getByText("Sample backend connected")).toBeInTheDocument();
  });

  it("explains that a disconnected backend can be retried", () => {
    render(<BackendStatus state="disconnected" />);

    expect(screen.getByText("Sample backend unavailable")).toBeInTheDocument();
    expect(screen.getByText(/Start the TypeScript backend/)).toBeInTheDocument();
  });
});
