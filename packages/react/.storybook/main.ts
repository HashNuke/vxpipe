import type { StorybookConfig } from "@storybook/react-vite";

const config: StorybookConfig = {
  stories: ["../stories/**/*.stories.tsx"],
  framework: "@storybook/react-vite",
  core: { disableTelemetry: true },
  typescript: { reactDocgen: false },
  viteFinal: async (config) => ({
    ...config,
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
