import { expect, test } from "vitest";

import { formatAdminRelativeTime } from "./formatAdminRelativeTime";

const now = new Date("2026-09-18T12:00:00.000Z");

test("formats service timestamps as compact relative values", () => {
  expect(formatAdminRelativeTime("2026-09-18T11:59:45.000Z", now)).toBe("just now");
  expect(formatAdminRelativeTime("2026-09-18T11:57:00.000Z", now)).toBe("3 minutes ago");
  expect(formatAdminRelativeTime("2026-09-15T12:00:00.000Z", now)).toBe("3 days ago");
});
