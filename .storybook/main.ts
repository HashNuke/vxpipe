import type { StorybookConfig } from "@storybook/react-vite";
import tailwindcss from "@tailwindcss/vite";

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
    plugins: [...(config.plugins ?? []), tailwindcss()],
    resolve: {
      ...config.resolve,
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
