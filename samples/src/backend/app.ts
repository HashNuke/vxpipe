import Fastify, {
  type FastifyInstance,
  type FastifyServerOptions,
} from "fastify";

const samples = [
  {
    description:
      "Send microphone audio to a room and subscribe to the agent output track.",
    id: "websocket-voice-room",
    status: "planned",
    title: "WebSocket voice room",
  },
] as const;

export type BuildServerOptions = Pick<FastifyServerOptions, "logger">;

export function buildServer(
  options: BuildServerOptions = { logger: false },
): FastifyInstance {
  const server = Fastify(options);

  server.get(
    "/api/health",
    {
      schema: {
        response: {
          200: {
            type: "object",
            additionalProperties: false,
            required: ["service", "status"],
            properties: {
              service: { const: "vxpipe-samples", type: "string" },
              status: { const: "ok", type: "string" },
            },
          },
        },
      },
    },
    async () => ({ service: "vxpipe-samples", status: "ok" }),
  );

  server.get(
    "/api/samples",
    {
      schema: {
        response: {
          200: {
            type: "object",
            additionalProperties: false,
            required: ["samples"],
            properties: {
              samples: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["description", "id", "status", "title"],
                  properties: {
                    description: { type: "string" },
                    id: { type: "string" },
                    status: { enum: ["available", "planned"], type: "string" },
                    title: { type: "string" },
                  },
                },
              },
            },
          },
        },
      },
    },
    async () => ({ samples }),
  );

  return server;
}
