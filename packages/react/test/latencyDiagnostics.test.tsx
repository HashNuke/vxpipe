import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import { LatencyDiagnostics } from "../src/LatencyDiagnostics.js";
import { createLatencyFixture, latencyReport, latencyTurns } from "../stories/latencyFixtures.js";

const open = () => fireEvent.click(screen.getByRole("button", { name: "Latency diagnostics" }));

test("diagnostics is collapsed and does not read until explicitly opened", async () => {
  const loader = { report: vi.fn(createLatencyFixture().report), turns: vi.fn(createLatencyFixture().turns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  expect(screen.getByRole("button", { name: "Latency diagnostics" })).toHaveAttribute("aria-expanded", "false");
  expect(loader.report).not.toHaveBeenCalled();
  open();
  expect(await screen.findByText("425 ms")).toBeVisible();
  expect(loader.report).toHaveBeenCalledTimes(1);
  expect(loader.turns).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByText("Whole-call summaries"));
  expect(screen.getByText(/1 valid/)).toBeVisible();
  expect(screen.getByText(/Incomplete/)).toBeVisible();
});

test("a failed report can be retried without enabling capture", async () => {
  const loader = createLatencyFixture();
  const report = vi.fn().mockRejectedValueOnce(new Error("unavailable")).mockResolvedValue(latencyReport);
  render(<LatencyDiagnostics loader={{ ...loader, report }} live={false} participants={[]} />);
  open();
  expect(await screen.findByRole("alert")).toHaveTextContent("could not be loaded");
  fireEvent.click(screen.getByRole("button", { name: "Retry diagnostics" }));
  expect(await screen.findByText("425 ms")).toBeVisible();
});

test("empty reports say not collected instead of zero latency", async () => {
  render(<LatencyDiagnostics loader={createLatencyFixture("empty")} live={false} participants={[]} />);
  open();
  expect(await screen.findByText(/Not collected/)).toBeVisible();
  expect(screen.queryByText("0 ms")).not.toBeInTheDocument();
});

test("closing aborts pending reads and ignores their late result", async () => {
  let finish!: (value: typeof latencyReport) => void;
  let signal!: AbortSignal;
  const loader = { report: vi.fn((_cursor, nextSignal) => { signal = nextSignal; return new Promise<typeof latencyReport>(resolve => { finish = resolve; }); }), turns: vi.fn().mockResolvedValue(latencyTurns) };
  render(<LatencyDiagnostics loader={loader} live={true} participants={[]} />);
  open();
  await waitFor(() => expect(loader.report).toHaveBeenCalledTimes(1));
  open();
  expect(signal.aborted).toBe(true);
  await act(async () => { finish(latencyReport); });
  expect(loader.turns).not.toHaveBeenCalled();
  expect(screen.queryByText("425 ms")).not.toBeInTheDocument();
});

test("refresh preserves an expanded row and ignores an older turn revision", async () => {
  const newer = { ...latencyTurns, turns: [{ ...latencyTurns.turns[0]!, revision: 5,
    durationsUs: { ...latencyTurns.turns[0]!.durationsUs, speech_end_to_provider_end: 999000 } }] };
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValueOnce(newer).mockResolvedValue(latencyTurns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  expect(await screen.findByText("999 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Turn 1" }));
  expect(screen.getByText("Estimated speech end")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(2));
  expect(screen.getByText("999 ms")).toBeVisible();
  expect(screen.getByRole("button", { name: "Turn 1" })).toHaveAttribute("aria-expanded", "true");
});

test("a turn-page mismatch cannot display another run's evidence", async () => {
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValue({ ...latencyTurns, runId: "foreign" }) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  expect(await screen.findByRole("alert")).toHaveTextContent("could not be loaded");
  expect(screen.queryByText("425 ms")).not.toBeInTheDocument();
});

test("revoked access hides previously loaded evidence", async () => {
  const report = vi.fn().mockResolvedValueOnce(latencyReport).mockRejectedValue({ status: 403 });
  render(<LatencyDiagnostics loader={{ report, turns: vi.fn().mockResolvedValue(latencyTurns) }} live={false} participants={[]} />);
  open();
  expect(await screen.findByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("do not have access");
  expect(screen.queryByText("425 ms")).not.toBeInTheDocument();
});

test("live refresh is paced and stops when the panel closes", async () => {
  vi.useFakeTimers();
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValue(latencyTurns) };
  const view = render(<LatencyDiagnostics loader={loader} live={true} participants={[]} />);
  try {
    open();
    await act(async () => {});
    expect(loader.report).toHaveBeenCalledTimes(1);
    await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
    expect(loader.report).toHaveBeenCalledTimes(2);
    open();
    await act(async () => { await vi.advanceTimersByTimeAsync(15000); });
    expect(loader.report).toHaveBeenCalledTimes(2);
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("an empty later observation page can return to the first page without claiming no collection", async () => {
  const loader = { report: vi.fn().mockResolvedValueOnce({ ...latencyReport, nextCursor: "later" })
    .mockResolvedValue({ runs: [], summary: latencyReport.summary, nextCursor: null }), turns: vi.fn().mockResolvedValue(latencyTurns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  expect(await screen.findByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Next observations" }));
  expect(await screen.findByText("No observations on this page.")).toBeVisible();
  expect(screen.queryByText(/Not collected/)).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "First observations" })).toBeEnabled();
});
