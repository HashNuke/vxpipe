import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import { LatencyDiagnostics } from "../src/LatencyDiagnostics.js";
import { BargeInEvidence, BargeInSummary } from "../src/BargeInEvidence.js";
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
  expect(screen.getByText(/End-of-turn detection: median Unavailable, p95 Unavailable · 0 valid, 123 excluded/)).toBeVisible();
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

test("late evidence revises an incomplete row without resetting expansion or keyboard focus", async () => {
  vi.useFakeTimers();
  const view = render(<LatencyDiagnostics loader={createLatencyFixture("late")} live={true} participants={[]} />);
  try {
    open();
    await act(async () => {});
    expect(screen.getByText(/1 pending/)).toBeVisible();
    expect(screen.queryByText("425 ms")).not.toBeInTheDocument();
    const turn = screen.getByRole("button", { name: "Turn 1" });
    fireEvent.click(turn);
    turn.focus();
    expect(screen.getByText(/Revision 1/)).toBeVisible();
    await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
    expect(screen.getByText("425 ms")).toBeVisible();
    expect(screen.getByText(/0 pending/)).toBeVisible();
    expect(screen.getByText(/Revision 2/)).toBeVisible();
    expect(turn).toHaveFocus();
    expect(turn).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("button", { name: "Latency diagnostics" })).toHaveAttribute("aria-expanded", "true");
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("the recoverable outage fixture loads evidence only after an explicit retry", async () => {
  render(<LatencyDiagnostics loader={createLatencyFixture("retry")} live={false} participants={[]} />);
  open();
  expect(await screen.findByRole("alert")).toHaveTextContent("could not be loaded");
  expect(screen.queryByText(/Not collected/)).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Retry diagnostics" }));
  expect(await screen.findByText("425 ms")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});

test.each([401, 403, 404])("turn read denial %s removes previously loaded summaries and rows", async status => {
  const turns = vi.fn().mockResolvedValueOnce(latencyTurns).mockRejectedValue({ status });
  render(<LatencyDiagnostics loader={{ report: async () => latencyReport, turns }} live={false} participants={[]} />);
  open();
  expect(await screen.findByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("do not have access");
  expect(screen.queryByText("425 ms")).not.toBeInTheDocument();
  expect(screen.queryByText("Whole-call summaries")).not.toBeInTheDocument();
});

test("a failed turn refresh retains labelled previous evidence and can recover", async () => {
  const turns = vi.fn().mockResolvedValueOnce(latencyTurns).mockRejectedValueOnce({ status: 503 }).mockResolvedValue(latencyTurns);
  render(<LatencyDiagnostics loader={{ report: async () => latencyReport, turns }} live={false} participants={[]} />);
  open();
  expect(await screen.findByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Showing previously loaded evidence");
  expect(screen.getByText("425 ms")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry diagnostics" }));
  await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
  expect(screen.getByText("425 ms")).toBeVisible();
  expect(turns).toHaveBeenCalledTimes(3);
});

const segmentEvidence = {
  version: 1 as const, omittedCount: 2, reasons: ["segment_limit"], entries: [
    { epoch: 0, startSample: 0, endSample: 16000, startUs: 0, endUs: 1000000,
      startConfirmedUs: 128000, endConfirmedUs: 1512000, uncertaintyUs: 32000, reasons: [] },
    { epoch: 1, startSample: null, endSample: 32000, startUs: null, endUs: 2000000,
      startConfirmedUs: null, endConfirmedUs: 2512000, uncertaintyUs: null, reasons: ["partial_start"] },
  ],
};

test("turn expansion reveals local segments without promoting them to conversational turns", async () => {
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValue({ ...latencyTurns,
    turns: [{ ...latencyTurns.turns[0]!, acousticSegments: segmentEvidence }] }) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  const button = await screen.findByRole("button", { name: "Turn 1" });
  expect(screen.queryByRole("table", { name: "Speech segments" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Turn 2" })).not.toBeInTheDocument();
  fireEvent.click(button);
  const segments = screen.getByRole("table", { name: "Speech segments" });
  expect(within(segments).getByText("0 ms")).toBeVisible();
  expect(within(segments).getByText("1,000 ms")).toBeVisible();
  expect(within(segments).getByText("Confirmed 1,512 ms")).toBeVisible();
  expect(within(segments).getByText("Sample 0")).toBeVisible();
  expect(within(segments).getByText("partial start")).toBeVisible();
  expect(within(segments).getAllByText(/Unavailable/).length).toBeGreaterThan(0);
  expect(screen.getByText("2 additional segments omitted (segment limit).")).toBeVisible();
});

test("legacy unavailable segments differ from an observed empty collection", async () => {
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValue({ ...latencyTurns,
    turns: [latencyTurns.turns[0]!, { ...latencyTurns.turns[1]!, acousticSegments: { version: 1, entries: [], omittedCount: 0, reasons: [] } }] }) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  fireEvent.click(await screen.findByRole("button", { name: "Turn 1" }));
  expect(within(screen.getByRole("table", { name: "Per-turn latency" })).getByText("Speech segment evidence unavailable.")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Turn 2" }));
  expect(screen.getByText("No speech segments recorded.")).toBeVisible();
});

test("participant selection keeps unattached segments and input runs isolated", async () => {
  const fixture = createLatencyFixture("participants", "second");
  const loader = { report: vi.fn(fixture.report), turns: vi.fn(fixture.turns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[{ id: "caller", name: "Caller" }, { id: "second", name: "Second human" }]} />);
  open();
  const selector = await screen.findByRole("combobox", { name: "Observation" });
  expect(within(selector).getAllByRole("option")).toHaveLength(2);
  fireEvent.click(await screen.findByRole("button", { name: "Turn 1" }));
  fireEvent.click(screen.getByRole("button", { name: "Turn 2" }));
  expect(screen.getAllByText(/Clock: clock-one/)).toHaveLength(2);
  const disclosure = await screen.findByText("Speech outside recorded turns");
  expect(disclosure.closest("details")).not.toHaveAttribute("open");
  fireEvent.click(disclosure);
  expect(screen.getByRole("table", { name: "Unattached speech segments" })).toBeVisible();
  fireEvent.change(selector, { target: { value: "run-second" } });
  await waitFor(() => expect(loader.turns).toHaveBeenLastCalledWith("run-second", null, expect.any(AbortSignal)));
  expect(screen.queryByRole("table", { name: "Unattached speech segments" })).not.toBeInTheDocument();
  fireEvent.click(await screen.findByRole("button", { name: "Turn 1" }));
  expect(screen.getByText(/Clock: clock-second/)).toBeVisible();
  expect(screen.queryByText("partial start")).not.toBeInTheDocument();
  expect(screen.queryByText(/Clock: clock-one/)).not.toBeInTheDocument();
});

test("refresh retains newer unattached evidence while equal-revision coverage can change", async () => {
  const run = { ...latencyReport.runs[0]!, revision: 5, unattachedSegments: segmentEvidence };
  const report = vi.fn().mockResolvedValueOnce({ ...latencyReport, runs: [run] })
    .mockResolvedValueOnce({ ...latencyReport, runs: [{ ...run, revision: 4, unattachedSegments: null }] })
    .mockResolvedValue({ ...latencyReport, runs: [{ ...run, unattachedSegments: null,
      coverage: { ...run.coverage, storedTurns: 9 } }] });
  const loader = { report, turns: vi.fn().mockResolvedValue(latencyTurns) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  fireEvent.click(await screen.findByText("Speech outside recorded turns"));
  expect(screen.getByRole("table", { name: "Unattached speech segments" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  await waitFor(() => expect(loader.turns).toHaveBeenCalledTimes(2));
  expect(screen.getByRole("table", { name: "Unattached speech segments" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  await waitFor(() => expect(screen.getByText(/9 stored turns/)).toBeVisible());
  expect(screen.getByRole("table", { name: "Unattached speech segments" })).toBeVisible();
});

const bargeInEvidence = { version: 1 as const, omittedCount: 0, reasons: [], entries: [{
  outputId: "old-output", agentParticipantId: "agent", responseSourceParticipantId: "other-human",
  outputConnectionId: "other-browser", responseTurnId: "old-turn", responseCommandId: "old-command",
  playbackStartedUs: 100000, interruptionRequestedUs: 350000, playbackStoppedUs: 380000,
  speechStartedUs: 300000, speechStartConfirmedUs: 450000, speechStartSample: 4800,
  epoch: 0, uncertaintyUs: 32000, durationUs: 80000, boundary: "server_egress" as const, reasons: [],
}] };

test("prioritizes end-of-turn and barge-in delays while preserving interrupted-output identity", async () => {
  const turns = { ...latencyTurns, turns: [{ ...latencyTurns.turns[0]!, bargeIn: bargeInEvidence }] };
  render(<LatencyDiagnostics loader={{ report: async () => latencyReport, turns: async () => turns }} live={false}
    participants={[{ id: "agent", name: "Voice agent" }, { id: "other-human", name: "Other caller" }]} />);
  open();
  expect(await screen.findByText("80 ms")).toBeVisible();
  expect(screen.getAllByRole("columnheader").map(item => item.textContent)).toEqual([
    "Human turn", "End-of-turn detection", "Barge-in stop delay", "Evidence",
  ]);
  const toggle = screen.getByRole("button", { name: "Turn 1" });
  expect(toggle).toHaveAttribute("aria-expanded", "false");
  expect(screen.queryByText("Dispatch")).not.toBeInTheDocument();
  fireEvent.click(toggle);
  const evidence = screen.getByRole("region", { name: "Barge-in evidence" });
  expect(within(evidence).getByText("80 ms")).toBeVisible();
  expect(within(evidence).getByText("300 ms")).toBeVisible();
  expect(within(evidence).getByText("380 ms")).toBeVisible();
  expect(within(evidence).getByText(/Confirmed 450 ms/)).toBeVisible();
  expect(within(evidence).getByText(/Voice agent.*Other caller/)).toBeVisible();
  expect(within(evidence).getByText("old-output")).toBeVisible();
  expect(within(evidence).getByText(/server.*stop acknowledgement/i)).toBeVisible();
  expect(screen.getByText("Dispatch")).toBeVisible();
});

test("late barge-in confirmation revises an unavailable duration without losing expansion", async () => {
  const available = { ...latencyTurns, turns: [{ ...latencyTurns.turns[0]!, revision: 2, bargeIn: bargeInEvidence }] };
  const pending = { ...available, turns: [{ ...available.turns[0]!, revision: 1, bargeIn: { ...bargeInEvidence,
    entries: [{ ...bargeInEvidence.entries[0]!, durationUs: null, speechStartedUs: null,
      speechStartConfirmedUs: null, speechStartSample: null, epoch: null, uncertaintyUs: null, reasons: ["missing_evidence"] }] } }] };
  const loader = { report: async () => latencyReport, turns: vi.fn().mockResolvedValueOnce(pending).mockResolvedValue(available) };
  render(<LatencyDiagnostics loader={loader} live={false} participants={[]} />);
  open();
  fireEvent.click(await screen.findByRole("button", { name: "Turn 1" }));
  const evidence = screen.getByRole("region", { name: "Barge-in evidence" });
  expect(within(evidence).getByText("missing evidence")).toBeVisible();
  expect(within(evidence).queryByText("0 ms")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  await waitFor(() => expect(within(evidence).getByText("80 ms")).toBeVisible());
  expect(screen.getByRole("button", { name: "Turn 1" })).toHaveAttribute("aria-expanded", "true");
});


test("positive sub-millisecond barge-in uncertainty is not displayed as zero", () => {
  const evidence = { ...bargeInEvidence, entries: [{ ...bargeInEvidence.entries[0]!,
    playbackStartedUs: 10000, speechStartedUs: 20000, interruptionRequestedUs: 30000,
    playbackStoppedUs: 35000, speechStartConfirmedUs: 40000, speechStartSample: 320,
    uncertaintyUs: 100, durationUs: 15000,
  }] };
  render(<BargeInEvidence evidence={evidence} name={id => id} />);
  expect(screen.getByText("20 ms")).toBeVisible();
  expect(screen.getByText("35 ms")).toBeVisible();
  expect(screen.getByText("15 ms")).toBeVisible();
  expect(screen.getByText("Uncertainty <1 ms")).toBeVisible();
  expect(screen.queryByText("Uncertainty 0 ms")).not.toBeInTheDocument();
});

test.each([
  [1, "<1 ms"], [100, "<1 ms"], [999, "<1 ms"], [0, "0 ms"],
  [null, "Unavailable"], [1000, "1 ms"], [15000, "15 ms"],
] as const)("barge-in summary preserves the distinction for %s microseconds", (durationUs, label) => {
  const evidence = { ...bargeInEvidence, entries: [{ ...bargeInEvidence.entries[0]!, durationUs }] };
  render(<BargeInSummary evidence={evidence} />);
  expect(screen.getByText(label)).toBeVisible();
});
