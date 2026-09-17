import { expect, test } from "vitest";

import { applyCredentialCreation, serviceFixture } from "./serviceFixtures";

test("rejects duplicate provider and credential-name bindings without overwrite", () => {
  const state = serviceFixture("populated");
  const result = applyCredentialCreation(state, {
    provider: "google",
    name: "primary",
    values: { apiKey: "replacement-value" },
  });

  expect(result.status).toBe("ready");
  if (result.status !== "ready" || state.status !== "ready") return;
  expect(result.services).toEqual(state.services);
  expect(result.setup.status).toBe("conflict");
  expect(JSON.stringify(result)).not.toContain("replacement-value");
});

test("stores only new credential metadata and does not imply telephony registration", () => {
  const result = applyCredentialCreation(serviceFixture("populated"), {
    provider: "twilio",
    name: "secondary",
    values: {
      accountSid: "AC00000000000000000000000000000000",
      authToken: "private-input",
    },
  });

  expect(result.status).toBe("ready");
  if (result.status !== "ready") return;
  expect(result.services.at(-1)).toMatchObject({
    provider: "twilio",
    credentialName: "secondary",
    serviceStatus: "not-registered",
  });
  expect(JSON.stringify(result)).not.toContain("private-input");
  expect(result.setup).toEqual({
    open: false,
    status: "success",
    resultVersion: 1,
  });
});
