import { AuthenticationApi, type ConnectedClient } from "./authenticationApi";

export type ConnectionsScenario = "connected" | "empty" | "loading" | "unavailable" | "revoke-failure" | "revoking";

/** In-memory adapter: exercises the real account component without sending requests. */
export function connectedClientsFixture(scenario: ConnectionsScenario = "connected") {
  let connections: ConnectedClient[] = scenario === "empty" ? [] : [
    { public_id: "example-codex", client_name: "Codex", resource: "https://voice.example.test/mcp", inserted_at: "2026-11-11T12:00:00Z", expires_at: "2026-12-11T12:00:00Z" },
    { public_id: "example-research", client_name: "Research assistant", resource: "https://voice.example.test/mcp", inserted_at: "2026-11-06T12:00:00Z", expires_at: "2026-12-06T12:00:00Z" },
  ];
  let loadFailed = false;
  return new AuthenticationApi("storybook", async (input, init) => {
    const path = String(input);
    if (init?.method === "GET" && path === "/api/account/connections") {
      if (scenario === "loading") return new Promise<Response>(() => undefined);
      if (scenario === "unavailable" && !loadFailed) {
        loadFailed = true;
        return Response.json({ error: { code: "unavailable" } }, { status: 503 });
      }
      return Response.json({ connections });
    }
    if (init?.method === "DELETE" && path.startsWith("/api/account/connections/")) {
      if (scenario === "revoking") return new Promise<Response>(() => undefined);
      if (scenario === "revoke-failure") return Response.json({ error: { code: "unavailable" } }, { status: 503 });
      const id = decodeURIComponent(path.slice("/api/account/connections/".length));
      connections = connections.filter((connection) => connection.public_id !== id);
      return new Response(null, { status: 204 });
    }
    return Response.json({ error: { code: "not_found" } }, { status: 404 });
  });
}
