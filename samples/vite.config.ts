import { hostname } from "node:os";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const backendPort = Number.parseInt(
  process.env.SAMPLES_BACKEND_PORT ?? "4100",
  10,
);

if (!Number.isInteger(backendPort) || backendPort < 1 || backendPort > 65_535) {
  throw new Error("SAMPLES_BACKEND_PORT must be an integer between 1 and 65535");
}

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "dist/frontend",
  },
  server: {
    allowedHosts: [hostname()],
    port: 5173,
    proxy: {
      "/api": `http://127.0.0.1:${backendPort}`,
    },
  },
});
