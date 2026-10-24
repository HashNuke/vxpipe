import { expect, test } from "vitest";
import { normalizeInstanceUrl } from "./instanceUrl";

test.each([
  [" https://CALLS.example.test:443/ ", "https://calls.example.test"],
  ["https://calls.example.test:8443", "https://calls.example.test:8443"],
  ["http://localhost:6006", "http://localhost:6006"],
  ["http://[::1]:4001", "http://[::1]:4001"],
  ["https://calls.example.test:8443/admin/setup", "https://calls.example.test:8443"],
  ["https://calls.example.test/path/..", "https://calls.example.test"],
  ["https://calls.example.test/admin?tab=setup#url", "https://calls.example.test"],
  ["https://calls.example.test?", "https://calls.example.test"],
  ["https://calls.example.test#", "https://calls.example.test"],
])("accepts and normalizes %s", (value, url) => {
  expect(normalizeInstanceUrl(value)).toEqual({ url });
});

test.each([
  "calls.example.test", "http://calls.example.test", "https://user:secret@calls.example.test",
  "https://calls.example.test\\@elsewhere.test", "https://calls.example.test:0",
  "https://calls.example.test:65536", "https://@calls.example.test",
])("rejects %s as an installation origin", value => {
  expect(normalizeInstanceUrl(value)).toHaveProperty("error");
});
