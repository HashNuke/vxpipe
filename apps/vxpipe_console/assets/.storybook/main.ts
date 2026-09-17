import type { StorybookConfig } from "@storybook/react-vite";
import tailwindcss from "@tailwindcss/vite";

const config: StorybookConfig = {
  stories: ["../src/admin/**/*.stories.tsx"],
  framework: "@storybook/react-vite",
  core: { disableTelemetry: true },
  typescript: { reactDocgen: false },
  viteFinal: async (viteConfig) => ({
    ...viteConfig,
    plugins: [...(viteConfig.plugins ?? []), tailwindcss()],
    resolve: {
      ...viteConfig.resolve,
      dedupe: [...(viteConfig.resolve?.dedupe ?? []), "react", "react-dom"],
    },
    server: {
      ...viteConfig.server,
      watch: {
        ...viteConfig.server?.watch,
        usePolling: true,
        interval: 300,
        ignored: ["**/storybook-static/**"],
      },
    },
  }),
};

export default config;
