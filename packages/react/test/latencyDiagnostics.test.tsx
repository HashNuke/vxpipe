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

test("transcript actions require both a retained turn and the observed participant", async () => {
  const onTranscript = vi.fn();
  render(<LatencyDiagnostics loader={createLatencyFixture()} live={false} participants={[]}
    messages={[{ id: "wrong", participantId: "other", turnId: "turn-one", text: "same words", occurredAt: "2026-11-19T12:00:00Z", state: "final" }]}
    onTranscript={onTranscript} />);
  open();
  await screen.findByText("425 ms");
  expect(screen.queryByRole("button", { name: /View transcript/ })).not.toBeInTheDocument();
  expect(onTranscript).not.toHaveBeenCalled();
});

test("whole-call summaries retain every metric definition, counts and missing percentiles", async () => {
  const report = { ...latencyReport, summary: [
    { ...latencyReport.summary[0]!, metric: "provider_to_room" as const, validCount: 120, excludedCount: 3, p50Us: 12500, p95Us: 25000 },
    { ...latencyReport.summary[0]!, metric: "speech_end_to_provider_end" as const, validCount: 0, excludedCount: 123, p50Us: null, p95Us: null },
  ] };
  render(<LatencyDiagnostics loader={{ report: async () => report, turns: async () => ({ ...latencyTurns, turns: [] }) }} live={false} participants={[]} />);
  open();
  fireEvent.click(await screen.findByText("Whole-call summaries"));
  expect(screen.getByText(/Dispatch: median 13 ms, p95 25 ms · 120 valid, 3 excluded/)).toBeVisible();
  expect(screen.getByText(/STT latency: median Unavailable, p95 Unavailable · 0 valid, 123 excluded/)).toBeVisible();
  expect(screen.queryByText(/median 0 ms/)).not.toBeInTheDocument();
});

test.each([
  ["pending", /2 pending/], ["unsupported", /Coverage: incomplete \(unsupported\)/], ["denied", /do not have access/],
] as const)("the %s fixture exposes its actual evidence state", async (mode, label) => {
  render(<LatencyDiagnostics loader={createLatencyFixture(mode)} live={false} participants={[]} />);
  open();
  expect(await screen.findByText(label)).toBeVisible();
  expect(screen.queryByText("0 ms")).not.toBeInTheDocument();
});

test("a large report stays paged while summary counts cover the full report", async () => {
  render(<LatencyDiagnostics loader={createLatencyFixture("large")} live={false} participants={[]} />);
  open();
  expect(await screen.findByRole("button", { name: "Turn 100" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Turn 101" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Next turns" })).toBeEnabled();
  fireEvent.click(screen.getByText("Whole-call summaries"));
  expect(screen.getByText(/100 valid, 100 excluded/)).toBeVisible();
});

test("refresh preserves the expanded cohort when an earlier profile appears", async () => {
  let report = latencyReport;
  const loader = { report: vi.fn(async () => report), turns: vi.fn(async () => latencyTurns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  fireEvent.click(screen.getByRole("button", { name: "Latency diagnostics" }));
  fireEvent.click(await screen.findByText("Whole-call summaries"));
  const original = screen.getByText("Observation profile 1").closest("details")!;
  fireEvent.click(screen.getByText("Observation profile 1"));
  expect(original.open).toBe(true);
  report = { ...latencyReport, summary: [
    { ...latencyReport.summary[0]!, profile: { ...latencyReport.summary[0]!.profile, provider: "earlier-provider" } },
    ...latencyReport.summary,
  ] };
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  await waitFor(() => expect(loader.report).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(screen.queryByRole("status")).not.toBeInTheDocument());
  expect(screen.getByText("Observation profile 2").closest("details")!.open).toBe(true);
  expect(screen.getByText("Observation profile 1").closest("details")!.open).toBe(false);
});

test("pending fixture does not contradict its stored run reasons", async () => {
  const report = await createLatencyFixture("pending").report(null, new AbortController().signal);
  const run = report.runs[0]!;
  const nonTerminal = run.reasons.filter(reason => !["disabled", "call_ended"].includes(reason));
  expect(run.coverage.reasons).toEqual(expect.arrayContaining(nonTerminal));
  expect(run.coverage.terminationReasons).toEqual([]);
});
