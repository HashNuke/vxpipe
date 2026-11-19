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
