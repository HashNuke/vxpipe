import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import type { LatencyLoader, LatencyReport, LatencyTurnPage, Metric } from "@vxpipe/core";
import { Metrics } from "../src/Metrics.js";
import { createFixtureController } from "../stories/fixtureClient.js";
import { createLatencyFixture, latencyReport, latencyTurns } from "../stories/latencyFixtures.js";

const stt = (participantId: string, value: number): Metric => ({
  label: "Final transcript latency", value, unit: "milliseconds", source: "STT", description: "Final transcript",
  scope: { kind: "participant-capability", participantId, capability: "STT" },
});

function snapshot(metrics: Metric[] = [stt("caller", 200), stt("caller", 260)]) {
  const base = createFixtureController("conversation").getSnapshot();
  return { ...base, metrics, participants: [...base.participants,
    { ...base.participants[0]!, id: "second-caller", name: "Second participant", role: "human" as const }] };
}

function view(loader: LatencyLoader, options: { live?: boolean; metrics?: Metric[]; onTranscript?: (id: string) => void; messages?: boolean } = {}) {
  const data = snapshot(options.metrics);
  if (options.messages) data.messages = [...data.messages,
    { id: "turn-one-message", participantId: "caller", turnId: "turn-one", text: "Hello", occurredAt: "2026-11-19T12:00:00Z", state: "final" },
    { id: "wrong-participant", participantId: "second-caller", turnId: "turn-two", text: "Other", occurredAt: "2026-11-19T12:00:01Z", state: "final" }];
  return render(<Metrics snapshot={data} theme="dark"
    latency={{ loader, live: options.live ?? false, onTranscript: options.onTranscript }} />);
}

const eot = (target = "VAD, Caller") => screen.getByRole("group", { name: `End-of-turn detection summary for ${target}` });
const barge = (target = "VAD, Caller") => screen.getByRole("group", { name: `Barge-in stop delay summary for ${target}` });

test("diagnostics become a VAD row per participant with columns beside final transcript latency", async () => {
  const loader = { report: vi.fn(createLatencyFixture().report), turns: vi.fn(createLatencyFixture().turns) };
  view(loader);
  expect(loader.report).toHaveBeenCalledTimes(1);
  expect(await screen.findByRole("rowheader", { name: "VAD, Caller" })).toBeVisible();
  const headers = screen.getAllByRole("columnheader").map(header => header.getAttribute("aria-label") ?? header.textContent);
  const ftl = headers.indexOf("Final transcript latency");
  expect(headers.slice(ftl, ftl + 3)).toEqual(["Final transcript latency", "End-of-turn detection", "Barge-in stop delay"]);
  const rows = screen.getAllByRole("rowheader").map(header => header.getAttribute("aria-label"));
  expect(rows.indexOf("VAD, Caller")).toBe(rows.indexOf("STT, Caller") + 1);
  expect(screen.queryByRole("button", { name: "Latency diagnostics" })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
});

test("summaries use median, p95 and valid counts, never totals or zero for missing evidence", async () => {
  view(createLatencyFixture());
  await waitFor(() => expect(eot()).toHaveTextContent("Median425 ms"));
  expect(eot()).toHaveTextContent("p95425 ms");
  expect(eot()).toHaveTextContent("1 of 2 turns valid");
  expect(eot()).not.toHaveTextContent("Total");
  expect(barge()).toHaveTextContent("No interruptions");
  expect(screen.getByRole("group", { name: "Final transcript latency summary for STT, Caller" })).toHaveTextContent("Total");
});

test("zero valid samples stay unavailable", async () => {
  view(createLatencyFixture("zero-valid"));
  await waitFor(() => expect(eot()).toHaveTextContent("0 of 2 turns valid"));
  expect(eot()).toHaveTextContent("Unavailable");
  expect(screen.queryByText("0 ms")).not.toBeInTheDocument();
});

test("barge-in summary counts every interruption and keeps reasons out of the median", async () => {
  view(createLatencyFixture("barge-in"));
  await waitFor(() => expect(barge()).toHaveTextContent("Median160 ms"));
  expect(barge()).toHaveTextContent("1 of 3 interruptions valid");
});

test("the VAD row expands into per-turn measurements while STT stays summarized", async () => {
  view(createLatencyFixture("barge-in"), { metrics: [stt("caller", 200), stt("caller", 260)] });
  await screen.findByRole("rowheader", { name: "VAD, Caller" });
  expect(screen.queryByRole("button", { name: /Expand metrics for STT/ })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Expand metrics for VAD, Caller" }));
  expect(screen.getByRole("button", { name: "End-of-turn detection for VAD, Caller, turn 1: 425 ms" })).toBeVisible();
  expect(screen.getByRole("button", { name: "End-of-turn detection for VAD, Caller, turn 2: Unavailable, partial start" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Barge-in stop delay for VAD, Caller, turn 2: Unavailable, ambiguous boundary" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Barge-in stop delay for VAD, Caller, turn 3: Unavailable, stop unavailable" })).toBeVisible();
  expect(screen.getByRole("group", { name: "Final transcript latency summary for STT, Caller" })).toBeVisible();
});

test("a turn's details show supporting timings, segments and interrupted-output identity", async () => {
  view(createLatencyFixture("barge-in"));
  await screen.findByRole("rowheader", { name: "VAD, Caller" });
  fireEvent.click(screen.getByRole("button", { name: "Expand metrics for VAD, Caller" }));
  fireEvent.click(screen.getByRole("button", { name: "Barge-in stop delay for VAD, Caller, turn 1: 160 ms" }));
  const details = screen.getByRole("dialog", { name: "Turn 1, Caller" });
  expect(within(details).getByText("Room VAD")).toBeVisible();
  expect(within(details).getByText("Estimated speech end")).toBeVisible();
  expect(within(details).getByText("Dispatch")).toBeVisible();
  const evidence = within(details).getByRole("region", { name: "Barge-in evidence" });
  expect(within(evidence).getByText("previous-agent-output")).toBeVisible();
  expect(within(details).getByText(/not remote hearing/)).toBeVisible();
  fireEvent.keyDown(details, { key: "Escape" });
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
});

test("transcript links require the observed participant's own turn", async () => {
  const onTranscript = vi.fn();
  view(createLatencyFixture(), { onTranscript, messages: true });
  await screen.findByRole("rowheader", { name: "VAD, Caller" });
  fireEvent.click(screen.getByRole("button", { name: "Expand metrics for VAD, Caller" }));
  fireEvent.click(screen.getByRole("button", { name: /End-of-turn detection for VAD, Caller, turn 2:/ }));
  expect(within(screen.getByRole("dialog")).queryByRole("button", { name: "View transcript" })).not.toBeInTheDocument();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  fireEvent.click(screen.getByRole("button", { name: /End-of-turn detection for VAD, Caller, turn 1:/ }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "View transcript" }));
  expect(onTranscript).toHaveBeenCalledWith("turn-one-message");
});

test("participants and observation profiles never share a row", async () => {
  view(createLatencyFixture("participants"));
  await screen.findByRole("rowheader", { name: "VAD, Caller" });
  expect(screen.getByRole("rowheader", { name: "VAD, Second participant" })).toBeVisible();
  expect(eot("VAD, Second participant")).toHaveTextContent("0 of 1 turns valid");
  const header = screen.getByRole("rowheader", { name: "VAD, Second participant" });
  expect(header).not.toHaveTextContent(/reuse|benchmark|incomplete/);
  fireEvent.click(within(header).getByRole("button", { name: "Observation details for VAD, Second participant" }));
  const observation = screen.getByRole("dialog", { name: "Observation, Second participant" });
  expect(within(observation).getByText("Participant VAD")).toBeVisible();
  expect(observation).not.toHaveTextContent(/operational_reuse|operational reuse/);
  fireEvent.keyDown(observation, { key: "Escape" });
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  fireEvent.click(screen.getByRole("button", { name: "Observation details for VAD, Caller" }));
  expect(within(screen.getByRole("dialog", { name: "Observation, Caller" })).getByText("Room VAD")).toBeVisible();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());

  const mixed: LatencyReport = { ...latencyReport, runs: [latencyReport.runs[0]!,
    { ...latencyReport.runs[0]!, id: "run-reuse", profile: { ...latencyReport.runs[0]!.profile, inference_source: "operational_reuse" } }] };
  const turns = async (runId: string): Promise<LatencyTurnPage> => ({ ...latencyTurns, runId, turns: latencyTurns.turns.map(turn => ({ ...turn, runId })) });
  view({ report: async () => mixed, turns });
  await waitFor(() => expect(screen.getAllByRole("rowheader", { name: "VAD, Caller" })).toHaveLength(3));
});

test("observation details hold profile, coverage and speech outside recorded turns", async () => {
  view(createLatencyFixture("participants"));
  fireEvent.click(await screen.findByRole("button", { name: "Observation details for VAD, Caller" }));
  const details = screen.getByRole("dialog", { name: "Observation, Caller" });
  expect(within(details).getByText(/scribe_v2_realtime/)).toBeVisible();
  expect(within(details).getByText(/partial start/)).toBeVisible();
  expect(within(details).getByRole("table", { name: "Speech outside recorded turns" })).toBeVisible();
  expect(within(details).getByText(/3 additional segments omitted/)).toBeVisible();
});

test("pending coverage is in the observation details, not in the row label", async () => {
  view(createLatencyFixture("pending"), { live: true });
  const details = await screen.findByRole("button", { name: "Observation details for VAD, Caller" });
  expect(screen.getByRole("rowheader", { name: "VAD, Caller" })).not.toHaveTextContent(/pending/);
  fireEvent.click(details);
  expect(within(screen.getByRole("dialog", { name: "Observation, Caller" })).getByText("0 stored, 2 pending")).toBeVisible();
});

test("not collected and loading states are a single line, not zero latency", async () => {
  const { unmount } = view(createLatencyFixture("loading"));
  expect(screen.getByRole("status")).toHaveTextContent("Loading latency diagnostics");
  unmount();
  view(createLatencyFixture("empty"));
  expect(await screen.findByText(/Latency diagnostics were not collected/)).toBeVisible();
  expect(screen.queryByRole("rowheader", { name: /^VAD/ })).not.toBeInTheDocument();
  expect(screen.queryByText("0 ms")).not.toBeInTheDocument();
});

test("an outage can be retried and a failed refresh keeps labelled previous evidence", async () => {
  view(createLatencyFixture("retry"));
  expect(await screen.findByRole("alert")).toHaveTextContent("could not be loaded");
  fireEvent.click(screen.getByRole("button", { name: "Retry diagnostics" }));
  await waitFor(() => expect(eot()).toHaveTextContent("Median425 ms"));
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});

test("a transient turn failure keeps previous evidence and retry recovers", async () => {
  const turns = vi.fn().mockResolvedValueOnce(latencyTurns).mockRejectedValueOnce({ status: 503 }).mockResolvedValue(latencyTurns);
  view({ report: async () => latencyReport, turns });
  await waitFor(() => expect(eot()).toHaveTextContent("Median425 ms"));
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Showing previously loaded evidence");
  expect(eot()).toHaveTextContent("Median425 ms");
  fireEvent.click(screen.getByRole("button", { name: "Retry diagnostics" }));
  await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
  expect(turns).toHaveBeenCalledTimes(3);
});

test.each([401, 403, 404])("denial %s removes previously loaded rows", async status => {
  const turns = vi.fn().mockResolvedValueOnce(latencyTurns).mockRejectedValue({ status });
  view({ report: async () => latencyReport, turns });
  await screen.findByRole("rowheader", { name: "VAD, Caller" });
  fireEvent.click(screen.getByRole("button", { name: "Refresh diagnostics" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("do not have access");
  expect(screen.queryByRole("rowheader", { name: "VAD, Caller" })).not.toBeInTheDocument();
});

test("a turn page for another run is rejected", async () => {
  view({ report: async () => latencyReport, turns: async () => ({ ...latencyTurns, runId: "foreign" }) });
  expect(await screen.findByRole("alert")).toHaveTextContent("could not be loaded");
  expect(screen.queryByRole("rowheader", { name: "VAD, Caller" })).not.toBeInTheDocument();
});

test("turn pages are read up to a bound and the row says how many turns it covers", async () => {
  let page = 0;
  const turns = vi.fn(async (_runId: string, cursor: string | null) => {
    page++;
    return { ...latencyTurns, nextCursor: `page-${page}`, turns: Array.from({ length: 50 }, (_, index) =>
      ({ ...latencyTurns.turns[0]!, turnId: `${cursor ?? "first"}-${index}` })) };
  });
  view({ report: async () => latencyReport, turns });
  await waitFor(() => expect(eot()).toHaveTextContent("200 of 200 turns valid"));
  expect(turns).toHaveBeenCalledTimes(4);
  expect(eot()).toHaveTextContent("First 200 loaded turns");
});

test("live refresh revises late evidence without collapsing the row and ignores older revisions", async () => {
  vi.useFakeTimers();
  const rendered = view(createLatencyFixture("late"), { live: true });
  try {
    await act(async () => {});
    expect(eot()).toHaveTextContent("0 of 1 turns valid");
    fireEvent.click(screen.getByRole("button", { name: "Expand metrics for VAD, Caller" }));
    await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
    expect(screen.getByRole("button", { name: "End-of-turn detection for VAD, Caller, turn 1: 425 ms" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Collapse metrics for VAD, Caller" })).toHaveAttribute("aria-expanded", "true");
  } finally { rendered.unmount(); vi.useRealTimers(); }
});

test("live refresh is paced and stops when the table unmounts", async () => {
  vi.useFakeTimers();
  const loader = { report: vi.fn().mockResolvedValue(latencyReport), turns: vi.fn().mockResolvedValue(latencyTurns) };
  const rendered = view(loader, { live: true });
  try {
    await act(async () => {});
    expect(loader.report).toHaveBeenCalledTimes(1);
    await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
    expect(loader.report).toHaveBeenCalledTimes(2);
    rendered.unmount();
    await act(async () => { await vi.advanceTimersByTimeAsync(15000); });
    expect(loader.report).toHaveBeenCalledTimes(2);
  } finally { vi.useRealTimers(); }
});

test("without metrics the table still shows collected diagnostics", async () => {
  view(createLatencyFixture(), { metrics: [] });
  expect(await screen.findByRole("rowheader", { name: "VAD, Caller" })).toBeVisible();
  expect(screen.queryByText("No metrics recorded.")).not.toBeInTheDocument();
});
