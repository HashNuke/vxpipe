import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import type { StorybookConfig } from "@storybook/react-vite";
import tailwindcss from "@tailwindcss/vite";
import { loadEnv } from "vite";
import { setupPublicOrigin } from "../apps/vxpipe_console/assets/src/admin/setupPublicOrigin.ts";

const publicSettings = loadEnv("development", process.cwd(), [
  "APP_HOST",
  "PORT",
  "VXPIPE_DEV_TLS",
]);
const publicOrigin = setupPublicOrigin({
  APP_HOST: process.env.APP_HOST ?? publicSettings.APP_HOST,
  PORT: execFileSync("bin/worktree-port", ["console"], {
    encoding: "utf8",
    env: { ...process.env, PORT: process.env.PORT ?? publicSettings.PORT ?? "" },
  }).trim(),
  VXPIPE_DEV_TLS: process.env.VXPIPE_DEV_TLS ?? publicSettings.VXPIPE_DEV_TLS,
});

const config: StorybookConfig = {
  stories: [
    "../packages/react/stories/**/*.stories.tsx",
    "../apps/vxpipe_console/assets/src/admin/**/*.stories.tsx",
  ],
  framework: "@storybook/react-vite",
  core: { disableTelemetry: true },
  typescript: { reactDocgen: false },
  viteFinal: async (config) => ({
    ...config,
    define: {
      ...config.define,
      "import.meta.env.STORYBOOK_APP_ORIGIN": JSON.stringify(publicOrigin),
    },
    plugins: [...(config.plugins ?? []), tailwindcss()],
    resolve: {
      ...config.resolve,
      alias: { ...config.resolve?.alias, "@": fileURLToPath(new URL("../apps/vxpipe_console/assets/src", import.meta.url)) },
      dedupe: [...(config.resolve?.dedupe ?? []), "react", "react-dom"],
    },
    server: {
      ...config.server,
      watch: {
        ...config.server?.watch,
        usePolling: true,
        interval: 300,
        ignored: ["**/storybook-static/**", "**/dist/**"],
      },
    },
  }),
};

export default config;
