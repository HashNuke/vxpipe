import type { Preview } from "@storybook/react-vite";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/geist-mono/400.css";
import "../packages/react/src/styles.css";
import "../packages/react/stories/prototype.css";
import "../apps/vxpipe_console/assets/src/admin/admin.css";

const preview: Preview = {
  parameters: {
    layout: "fullscreen",
    options: {
      storySort: {
        order: [
          "Vxpipe",
          [
            "React",
            "Console",
            [
              "shared",
              "Tenants",
              ["components", "Directory", "My tenants", "Dashboard", "Create tenant", "Getting started", "Setup overview"],
              "Calls",
              ["components", "Calls", "History"],
              "Call Specs",
              ["components", "Call specs", "Sample call specs"],
              "Services",
              ["components", "Tenant services", "Platform services", "Tenant inventory", "API keys"],
              "Users",
              ["components", "Users", "Management journey"],
              "Roles",
              ["components", "Roles"],
              "My account",
              "Authentication",
              "Diagnostics",
              "Samples",
              "Call spec editor",
            ],
          ],
        ],
      },
    },
  },
};

export default preview;
