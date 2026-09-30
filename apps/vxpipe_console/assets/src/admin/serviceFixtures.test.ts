import { expect, test } from "vitest";

import { applyCredentialCreation, serviceFixture } from "./serviceFixtures";

test("rejects duplicate provider bindings without overwrite", () => {
  const state = serviceFixture("populated");
  const result = applyCredentialCreation(state, {
    provider: "google",
    values: { apiKey: "replacement-value" },
  });

  expect(result.status).toBe("ready");
  if (result.status !== "ready" || state.status !== "ready") return;
  expect(result.services).toEqual(state.services);
  expect(result.setup.status).toBe("conflict");
  expect(JSON.stringify(result)).not.toContain("replacement-value");
});

test("stores only new credential metadata", () => {
  const result = applyCredentialCreation(serviceFixture("populated"), {
    provider: "zenmux",
    values: { apiKey: "private-input" },
  });

  expect(result.status).toBe("ready");
  if (result.status !== "ready") return;
  expect(result.services.at(-1)).toMatchObject({
    provider: "zenmux",
    credentialName: "zenmux",
    updatedAt: expect.any(String),
  });
  expect(JSON.stringify(result)).not.toContain("private-input");
  expect(result.setup).toEqual({
    open: false,
    status: "success",
    resultVersion: 1,
  });
});

test("saving an ElevenLabs service does not claim upstream validation", () => {
  const result = applyCredentialCreation(serviceFixture("empty"), {
    provider: "elevenlabs",
    values: { apiKey: "synthetic-private-input" },
  });

  expect(result.status).toBe("ready");
  if (result.status !== "ready") return;
  expect(result.services.at(-1)).toMatchObject({
    provider: "elevenlabs",
    lastValidatedAt: null,
  });
  expect(JSON.stringify(result)).not.toContain("synthetic-private-input");
});
