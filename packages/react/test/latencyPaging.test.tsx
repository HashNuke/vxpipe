import { act, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import { useLatencyReport } from "../src/useLatencyReport.js";
import { LatencyDiagnostics } from "../src/LatencyDiagnostics.js";
import { latencyReport, latencyTurns } from "../stories/latencyFixtures.js";

test("empty successor does not claim this observation never had summaries", async () => {
  const loader = {
    report: vi.fn().mockResolvedValue(latencyReport),
    turns: vi.fn().mockResolvedValueOnce({ ...latencyTurns, nextCursor: "turn-two" }).mockResolvedValue({ runId: "run-one", turns: [], nextCursor: null }),
  };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  fireEvent.click(screen.getByRole("button", { name: "Latency diagnostics" }));
  expect(await screen.findByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Next turns" }));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(screen.queryByRole("status")).not.toBeInTheDocument());
  expect(screen.getByRole("button", { name: "First turns" })).toBeVisible();
  expect(screen.queryByText("No turn summaries in this observation yet.")).not.toBeInTheDocument();
});

test("inserting an earlier run preserves the selected observation and its cursor", async () => {
  let report = latencyReport;
  const loader = {
    report: vi.fn(async () => report),
    turns: vi.fn(async (id: string) => ({ ...latencyTurns, runId: id, turns: latencyTurns.turns.map(turn => ({ ...turn, runId: id })) })),
  };
  const view = renderHook(() => useLatencyReport(loader, true, false));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  expect(view.result.current.runId).toBe("run-one");
  act(() => view.result.current.pageTurns("turn-one"));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  report = { ...latencyReport, runs: [{ ...latencyReport.runs[0]!, id: "run-earlier" }, ...latencyReport.runs] };
  act(() => view.result.current.reload());
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(3));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  expect(loader.turns.mock.calls.at(-1)?.slice(0, 2)).toEqual(["run-one", "turn-one"]);
  expect(view.result.current.runId).toBe("run-one");
});

test("falling back when selected run leaves the page starts at its first turn", async () => {
  let report = latencyReport;
  const loader = {
    report: vi.fn(async () => report),
    turns: vi.fn(async (id: string) => ({ ...latencyTurns, runId: id, turns: latencyTurns.turns.map(turn => ({ ...turn, runId: id })) })),
  };
  const view = renderHook(() => useLatencyReport(loader, true, false));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  act(() => view.result.current.selectRun("run-one"));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  act(() => view.result.current.pageTurns("turn-one"));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(3));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  report = { ...latencyReport, runs: [{ ...latencyReport.runs[0]!, id: "run-earlier" }] };
  act(() => view.result.current.reload());
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(4));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  expect(loader.turns.mock.calls.at(-1)?.slice(0, 2)).toEqual(["run-earlier", null]);
});

test("a fallback observation stays selected when another earlier run arrives", async () => {
  let report = latencyReport;
  const loader = {
    report: vi.fn(async () => report),
    turns: vi.fn(async (id: string) => ({ ...latencyTurns, runId: id, turns: latencyTurns.turns.map(turn => ({ ...turn, runId: id })) })),
  };
  const view = renderHook(() => useLatencyReport(loader, true, false));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  act(() => view.result.current.selectRun("run-one"));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(2));
  report = { ...latencyReport, runs: [{ ...latencyReport.runs[0]!, id: "run-fallback" }] };
  act(() => view.result.current.reload());
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(3));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  expect(view.result.current.runId).toBe("run-fallback");
  report = { ...report, runs: [{ ...latencyReport.runs[0]!, id: "run-earlier" }, ...report.runs] };
  act(() => view.result.current.reload());
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(4));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  expect(view.result.current.runId).toBe("run-fallback");
});
