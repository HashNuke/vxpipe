import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "");
  const appHost = env.APP_HOST?.trim();
  const bindHost = env.VXPIPE_DEV_TLS === "caddy" ? "127.0.0.1" : appHost;
  const samplesPort = Number(env.VXPIPE_SAMPLES_PORT?.trim() || "5173");

  return {
    plugins: [react()],
    server: {
      host: bindHost || "0.0.0.0",
      allowedHosts: appHost ? [appHost] : [],
      port: samplesPort,
      strictPort: true,
      proxy: {
        "/api": {
          target: env.VXPIPE_GATEWAY_URL?.trim() || "http://127.0.0.1:4000",
          changeOrigin: true,
          ws: true,
        },
      },
    },
    test: {
      environment: "jsdom",
      setupFiles: "./src/test/setup.ts",
    },
  };
});
