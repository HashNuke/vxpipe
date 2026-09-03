import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "");
  const appHost = env.APP_HOST?.trim();
  const gatewayHost = appHost || "127.0.0.1";
  const bindHost = env.VXPIPE_DEV_TLS === "tailscale" ? "127.0.0.1" : appHost;

  return {
    plugins: [react()],
    server: {
      host: bindHost || "0.0.0.0",
      allowedHosts: appHost ? [appHost] : [],
      port: 5173,
      strictPort: true,
      proxy: {
        "/api": {
          target:
            env.VXPIPE_GATEWAY_URL?.trim() || `http://${gatewayHost}:4000`,
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
