import { describe, expect, it } from "vitest";
import { mergeLatencyTurns, type LatencyTurn, type LatencyTurnPage } from "../src/callLatency.js";

function turn(id: string, revision: number, value: number): LatencyTurn {
  return { runId: "run", turnId: id, revision, sttAllocationId: "stt", clockId: "clock", sourceEpoch: "source",
    providerTurnId: null, responseTurnId: null, landmarksUs: {}, durationsUs: { provider_to_room: value },
    metricReasons: {}, quality: "incomplete", acousticReason: null, acousticSample: null, uncertaintyUs: null };
}
function page(turns: LatencyTurn[], runId = "run"): LatencyTurnPage {
  return { runId, turns, nextCursor: null };
}

describe("latency turn refresh", () => {
  it("does not overwrite a later revision with stale or conflicting same-revision data", () => {
    const current = page([turn("one", 3, 300)]);
    expect(mergeLatencyTurns(current, page([turn("one", 2, 200)])).turns).toEqual(current.turns);
    expect(mergeLatencyTurns(current, page([turn("one", 3, 999)])).turns).toEqual(current.turns);
    expect(mergeLatencyTurns(current, page([turn("one", 4, 400)])).turns[0]?.durationsUs.provider_to_room).toBe(400);
  });
  it("keeps only the requested page, preserving revisions for overlapping rows", () => {
    const current = page([turn("one", 3, 300), turn("two", 3, 300)]);
    const next = { ...page([turn("two", 1, 100), turn("three", 1, 100)]), nextCursor: "three" };
    const merged = mergeLatencyTurns(current, next);
    expect(merged.turns.map(row => [row.turnId, row.revision])).toEqual([["two", 3], ["three", 1]]);
    expect(merged.nextCursor).toBe("three");
    expect(current.turns).toHaveLength(2);
  });
  it("never borrows revisions across observation runs", () => {
    const next = page([{ ...turn("one", 1, 100), runId: "other" }], "other");
    expect(mergeLatencyTurns(page([turn("one", 9, 900)]), next)).toEqual(next);
    expect(mergeLatencyTurns(undefined, next)).toEqual(next);
  });
});
