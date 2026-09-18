import { expect, test } from "vitest";
import { setupPublicOrigin, telnyxWebhookUrl } from "./setupPublicOrigin";

test("application origin uses localhost and app port locally, and HTTPS for a public APP_HOST", () => {
  expect(setupPublicOrigin({})).toBe("http://localhost:4000");
  expect(setupPublicOrigin({ APP_HOST: "localhost", PORT: "4567" })).toBe(
    "http://localhost:4567",
  );
  expect(
    setupPublicOrigin({ APP_HOST: "voice.example.test", PORT: "4000" }),
  ).toBe("https://voice.example.test");
  expect(
    setupPublicOrigin({
      APP_HOST: "voice.example.test",
      PORT: "4443",
      VXPIPE_DEV_TLS: "phoenix",
    }),
  ).toBe("https://voice.example.test:4443");
  expect(
    setupPublicOrigin({
      APP_HOST: "localhost",
      PORT: "4567",
      VXPIPE_DEV_TLS: "http",
    }),
  ).toBe("http://localhost:4567");
});

test("webhook construction keeps explicit scopes and encodes tenant identifiers", () => {
  expect(telnyxWebhookUrl("http://localhost:4000/", { kind: "platform" })).toBe(
    "http://localhost:4000/webhooks/platform/telnyx",
  );
  expect(
    telnyxWebhookUrl("https://voice.example.test", {
      kind: "tenant",
      tenantKey: "a/b",
      tenantName: "Team",
    }),
  ).toBe("https://voice.example.test/webhooks/tenants/a%2Fb/telnyx");
});
