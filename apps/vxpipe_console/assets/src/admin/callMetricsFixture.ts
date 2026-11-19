import type { CallDetailsSnapshot, Metric } from "@vxpipe/core";

/** Synthetic multi-turn measurements for the existing call-history Storybook. */
export function callMetricsFixture(): CallDetailsSnapshot["metrics"] {
  const turns = Array.from({ length: 12 }, (_, index) => {
    const turn = index + 1;
    const measurements: Array<[string, number | null, string, string]> = [
      ["Final transcript latency", 180 + (index % 4) * 35, "milliseconds", "STT"],
      ["TTFT", 290 + (index % 5) * 45, "milliseconds", "LLM"],
      ["Input tokens", 420 + index * 110, "tokens", "LLM"],
      ["Output tokens", 35 + (index % 3) * 12, "tokens", "LLM"],
      ["Time to first audio", index === 11 ? null : 80 + (index % 4) * 15, "milliseconds", "TTS"],
      ["Characters", 120 + (index % 4) * 40, "characters", "TTS"],
      ["Requests", 1, "requests", "TTS"],
    ];
    return measurements.map(([label, value, unit, capability]) => ({
      id: `fixture-metric-${capability}-${label}-${turn}`,
      revision: 1,
      value: {
        label, value, unit, source: capability === "STT" ? "STT · Caller session" : `${capability} · Turn ${turn}`,
        description: `Synthetic ${label.toLowerCase()} measurement for turn ${turn}.`,
        scope: { kind: "participant-capability", participantId: capability === "STT" ? "caller" : "assistant", capability },
      } satisfies Metric,
    }));
  }).flat();
  const secondSTT = turns.filter(metric => metric.value.scope.kind === "participant-capability" && metric.value.scope.capability === "STT")
    .map(metric => ({ ...metric, id: `${metric.id}-second`, value: { ...metric.value,
      value: (metric.value.value ?? 0) + 45, source: "STT · Second participant session",
      scope: { kind: "participant-capability" as const, participantId: "second-caller", capability: "STT" },
    } }));
  return [...turns, ...secondSTT];
}
