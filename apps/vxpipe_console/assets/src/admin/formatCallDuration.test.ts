import { expect, test } from "vitest";
import { formatCallDuration } from "./formatCallDuration";

test.each([[4326000, "1h 12m 6s"], [724000, "12m 4s"], [56999, "56s"], [0, "0s"], [null, "—"], [3600000, "1h"]])("formats finalized duration %s", (duration, label) => {
  expect(formatCallDuration(duration as number | null)).toBe(label);
});
