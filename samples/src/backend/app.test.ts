// @vitest-environment node

import { afterEach, describe, expect, it } from "vitest";

import { buildServer } from "./app.js";

const servers: Array<ReturnType<typeof buildServer>> = [];

afterEach(async () => {
  await Promise.all(servers.splice(0).map((server) => server.close()));
});

describe("sample backend", () => {
  it("reports its health without external dependencies", async () => {
    const server = buildServer();
    servers.push(server);

    const response = await server.inject({ method: "GET", url: "/api/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ service: "vxpipe-samples", status: "ok" });
  });

  it("publishes the dogfooding sample catalog", async () => {
    const server = buildServer();
    servers.push(server);

    const response = await server.inject({ method: "GET", url: "/api/samples" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      samples: [
        {
          description:
            "Send microphone audio to a room and subscribe to the agent output track.",
          id: "websocket-voice-room",
          status: "planned",
          title: "WebSocket voice room",
        },
      ],
    });
  });
});
