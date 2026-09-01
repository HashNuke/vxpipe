import { buildServer } from "./app.js";

const defaultPort = 4100;

function configuredPort(value: string | undefined): number {
  if (value === undefined) {
    return defaultPort;
  }

  const port = Number.parseInt(value, 10);

  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("SAMPLES_PORT must be an integer between 1 and 65535");
  }

  return port;
}

const host = process.env.SAMPLES_HOST ?? "127.0.0.1";
const port = configuredPort(process.env.SAMPLES_PORT);
const server = buildServer({ logger: true });

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    void server.close();
  });
}

try {
  await server.listen({ host, port });
} catch (error) {
  server.log.error({ error }, "Unable to start the sample backend");
  process.exitCode = 1;
}
