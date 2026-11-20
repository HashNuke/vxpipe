import serverContracts from "./test/latencyServerContracts.json";
import { expect, test, vi } from "vitest";
import { createCallLatencyLoader, parseLatencyReport, parseLatencyTurns } from "./callLatencyApi";
import { latencyResponseFixture, latencyTurnsFixture } from "./test/latencyResponseFixture";

test("decodes versioned timing without conflating missing data with zero or rounding raw precision", () => {
  const report = parseLatencyReport(latencyResponseFixture(), "call-public-id");
  expect(report.runs[0]).toMatchObject({ id: "run-one", revision: 3, clockId: "clock-one", settingsRevision: 2,
    coverage: { status: "complete", storedTurns: 1 } });
  expect(report.summary[0]).toMatchObject({ validCount: 1, p50Us: 20100.5 });
  const turns = parseLatencyTurns(latencyTurnsFixture(), "call-public-id", "run-one");
  expect(turns.turns[0]).toMatchObject({ revision: 4, uncertaintyUs: 32000,
    durationsUs: { provider_to_room: 20100, speech_end_to_provider_end: null },
    metricReasons: { speech_end_to_provider_end: "missing_evidence" } });
});

test("empty reports are valid and malformed, oversized or duplicate records are rejected", () => {
  const empty = { ...latencyResponseFixture(), runs: [], summary: [] };
  expect(parseLatencyReport(empty, "call-public-id").runs).toEqual([]);
  const base = latencyResponseFixture();
  for (const value of [
    { ...base, schema_version: 2 }, { ...base, call_id: "other" },
    { ...base, runs: Array(101).fill(base.runs[0]) }, { ...base, runs: [base.runs[0], base.runs[0]] },
    { ...base, runs: [{ ...base.runs[0], revision: 1.5 }] },
    { ...base, runs: [{ ...base.runs[0], profile: { ...base.runs[0]!.profile, secret: "unexpected" } }] },
    { ...base, summary: [{ ...base.summary[0], valid_count: Number.MAX_SAFE_INTEGER + 1 }] },
  ]) expect(() => parseLatencyReport(value, "call-public-id")).toThrow();
  const page = latencyTurnsFixture();
  for (const value of [
    { ...page, run_id: "other" }, { ...page, turns: [page.turns[0], page.turns[0]] },
    { ...page, turns: [{ ...page.turns[0], run_id: "other" }] },
    { ...page, turns: [{ ...page.turns[0], durations_us: { provider_to_room: -1 } }] },
    { ...page, turns: [{ ...page.turns[0], landmarks_us: { acoustic_end: NaN } }] },
  ]) expect(() => parseLatencyTurns(value, "call-public-id", "run-one")).toThrow();
});

test("loader is lazy, encodes scoped URLs, sends browser credentials and forwards abort", async () => {
  const fetchImpl = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify(latencyResponseFixture())))
    .mockResolvedValueOnce(new Response(JSON.stringify(latencyTurnsFixture())));
  const loader = createCallLatencyLoader("tenant/key", "call-public-id", { fetchImpl });
  expect(fetchImpl).not.toHaveBeenCalled();
  const abort = new AbortController();
  await loader.report("cursor + next", abort.signal);
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant%2Fkey/calls/call-public-id/latency?cursor=cursor+%2B+next", expect.objectContaining({ signal: abort.signal, credentials: "same-origin", cache: "no-store" }));
  await loader.turns("run-one", null, abort.signal);
  expect(fetchImpl).toHaveBeenLastCalledWith("/api/tenants/tenant%2Fkey/calls/call-public-id/latency/runs/run-one/turns", expect.any(Object));
});

test("expired sessions notify the current host but an aborted late response does not", async () => {
  const expired = vi.fn();
  const abort = new AbortController();
  const fetchImpl = vi.fn().mockResolvedValue(new Response("", { status: 401 }));
  const loader = createCallLatencyLoader("tenant", "call-public-id", { fetchImpl, onSessionExpired: expired });
  await expect(loader.report(null, abort.signal)).rejects.toMatchObject({ status: 401 });
  expect(expired).toHaveBeenCalledTimes(1);
  let release!: (response: Response) => void;
  fetchImpl.mockImplementationOnce(() => new Promise<Response>((resolve) => { release = resolve; }));
  const pending = loader.report(null, abort.signal);
  abort.abort();
  release(new Response("", { status: 401 }));
  await expect(pending).rejects.toThrow();
  expect(expired).toHaveBeenCalledTimes(1);
});

test("storage errors and malformed JSON stay separate from conversation loading", async () => {
  const fetchImpl = vi.fn().mockResolvedValueOnce(new Response("", { status: 503 }))
    .mockResolvedValueOnce(new Response("not JSON"));
  const loader = createCallLatencyLoader("tenant", "call-public-id", { fetchImpl });
  await expect(loader.report(null, new AbortController().signal)).rejects.toMatchObject({ status: 503 });
  await expect(loader.report(null, new AbortController().signal)).rejects.toThrow(/malformed/i);
});


test.each(Object.entries(serverContracts))("decodes the server-constructed %s profile", (_name, wire) => {
  const report = parseLatencyReport(wire, "call-1");
  expect(report.runs[0]?.profile).toEqual(wire.runs[0]!.profile);
});

const acousticEvidence = () => ({ version: 1, omitted_count: 2, reasons: ["segment_limit"],
  entries: [
    { epoch: 2, start_sample: 0, end_sample: 512, start_us: 0, end_us: 32000,
      start_confirmed_us: 128000, end_confirmed_us: 544000, uncertainty_us: 32000, reasons: [] },
    { epoch: 3, start_sample: null, end_sample: 512, start_us: null, end_us: null,
      start_confirmed_us: null, end_confirmed_us: 600000, uncertainty_us: null, reasons: ["partial_start", "clock_uncertain"] },
  ] });
function parseSegmentEvidence(evidence: unknown) {
  const page = latencyTurnsFixture();
  return parseLatencyTurns({ ...page, turns: [{ ...page.turns[0], acoustic_segments: evidence }] }, "call-public-id", "run-one").turns[0];
}

test("preserves segment boundaries, confirmations, loss and missing evidence in the enclosing source clock", () => {
  const evidence = acousticEvidence();
  const decoded = { version: 1, omittedCount: 2, reasons: ["segment_limit"], entries: [
    { epoch: 2, startSample: 0, endSample: 512, startUs: 0, endUs: 32000,
      startConfirmedUs: 128000, endConfirmedUs: 544000, uncertaintyUs: 32000, reasons: [] },
    { epoch: 3, startSample: null, endSample: 512, startUs: null, endUs: null,
      startConfirmedUs: null, endConfirmedUs: 600000, uncertaintyUs: null, reasons: ["partial_start", "clock_uncertain"] },
  ] };
  expect(parseSegmentEvidence(evidence)).toMatchObject({ acousticSegments: decoded, clockId: "clock-one", sourceEpoch: "source-one" });
  const report = latencyResponseFixture();
  expect(parseLatencyReport({ ...report, runs: [{ ...report.runs[0], unattached_segments: evidence }] }, "call-public-id").runs[0])
    .toMatchObject({ participantId: "caller", unattachedSegments: decoded });
  expect(parseSegmentEvidence({ version: 1, entries: [], omitted_count: 0, reasons: [] }))
    .toMatchObject({ acousticSegments: { version: 1, entries: [], omittedCount: 0, reasons: [] } });
});

test("legacy omitted and null segment fields stay unavailable", () => {
  expect(parseLatencyReport(latencyResponseFixture(), "call-public-id").runs[0]).toHaveProperty("unattachedSegments", null);
  expect(parseLatencyTurns(latencyTurnsFixture(), "call-public-id", "run-one").turns[0]).toHaveProperty("acousticSegments", null);
  expect(parseSegmentEvidence(null)).toHaveProperty("acousticSegments", null);
});

test("rejects unsupported, unbounded or contradictory acoustic evidence", () => {
  const base = acousticEvidence();
  const complete = base.entries[0]!;
  for (const evidence of [
    { ...base, version: 2 }, { ...base, omitted_count: -1 }, { ...base, omitted_count: 0.5 },
    { ...base, reasons: [] }, { ...base, reasons: ["unknown"] },
    { ...base, entries: Array(33).fill(complete) },
    { ...base, entries: [{ ...complete, end_us: -1 }] },
    { ...base, entries: [{ ...complete, start_confirmed_us: null }] },
    { ...base, entries: [{ ...complete, end_sample: null }] },
    { ...base, entries: [{ ...complete, start_sample: 513 }] },
    { ...base, entries: [{ ...complete, end_confirmed_us: 1 }] },
    { ...base, entries: [{ ...complete, epoch: Number.MAX_SAFE_INTEGER + 1 }] },
    { ...base, entries: [{ ...complete, uncertainty_us: 604800000001 }] },
    { ...base, entries: [{ ...complete, start_us: null }] },
    { ...base, entries: [complete, { ...complete, end_sample: 1024 }] },
  ]) {
    expect(() => parseSegmentEvidence(evidence)).toThrow(/malformed/i);
    const report = latencyResponseFixture();
    expect(() => parseLatencyReport({ ...report, runs: [{ ...report.runs[0], unattached_segments: evidence }] }, "call-public-id")).toThrow(/malformed/i);
  }
});

const bargeEvidence = () => ({ version: 1, omitted_count: 0, reasons: [], entries: [{
  output_id: "old-output", agent_participant_id: "agent", response_source_participant_id: "other-human",
  output_connection_id: "other-browser", response_turn_id: "old-turn", response_command_id: "old-command",
  playback_started_us: 100000, interruption_requested_us: 350000, playback_stopped_us: 380000,
  speech_started_us: 300000, speech_start_confirmed_us: 450000, speech_start_sample: 4800,
  epoch: 0, uncertainty_us: 32000, duration_us: 80000, boundary: "server_egress", reasons: [],
}] });
function parseBargeEvidence(evidence: unknown) {
  const page = latencyTurnsFixture();
  return parseLatencyTurns({ ...page, turns: [{ ...page.turns[0], barge_in: evidence }] }, "call-public-id", "run-one").turns[0];
}

test("decodes barge-in onset to acknowledged stop independently of later VAD confirmation", () => {
  expect(parseBargeEvidence(bargeEvidence())).toMatchObject({ bargeIn: { version: 1, omittedCount: 0, reasons: [], entries: [{
    outputId: "old-output", agentParticipantId: "agent", responseSourceParticipantId: "other-human",
    outputConnectionId: "other-browser", responseTurnId: "old-turn", responseCommandId: "old-command",
    playbackStartedUs: 100000, interruptionRequestedUs: 350000, playbackStoppedUs: 380000,
    speechStartedUs: 300000, speechStartConfirmedUs: 450000, speechStartSample: 4800,
    epoch: 0, uncertaintyUs: 32000, durationUs: 80000, boundary: "server_egress", reasons: [],
  }] } });
  expect(parseBargeEvidence(null)).toHaveProperty("bargeIn", null);
  expect(parseLatencyTurns(latencyTurnsFixture(), "call-public-id", "run-one").turns[0]).toHaveProperty("bargeIn", null);
});

test("rejects fabricated, unbounded or contradictory barge-in durations", () => {
  const base = bargeEvidence(), entry = base.entries[0]!;
  for (const evidence of [
    { ...base, version: 2 }, { ...base, entries: Array(33).fill(entry) },
    { ...base, omitted_count: 1 }, { ...base, reasons: ["unknown"] },
    { ...base, entries: [{ ...entry, transcript: "private" }] },
    { ...base, entries: [{ ...entry, duration_us: 0 }] },
    { ...base, entries: [{ ...entry, duration_us: null }] },
    { ...base, entries: [{ ...entry, playback_stopped_us: 290000 }] },
    { ...base, entries: [{ ...entry, interruption_requested_us: 390000 }] },
    { ...base, entries: [{ ...entry, speech_start_confirmed_us: 299999 }] },
    { ...base, entries: [{ ...entry, uncertainty_us: 604800000001 }] },
    { ...base, entries: [{ ...entry, boundary: "remote_hearing" }] },
    { ...base, entries: [{ ...entry, reasons: ["ambiguous_boundary"] }] },
  ]) expect(() => parseBargeEvidence(evidence)).toThrow(/malformed/i);
  expect(parseBargeEvidence({ ...base, entries: [{ ...entry, duration_us: null, speech_started_us: null,
    speech_start_confirmed_us: null, speech_start_sample: null, epoch: null, uncertainty_us: null,
    reasons: ["missing_evidence"] }] })).toMatchObject({ bargeIn: { entries: [{ durationUs: null, reasons: ["missing_evidence"] }] } });
});
