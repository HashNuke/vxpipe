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
              "Full journey",
              "Authentication",
              ["Full journey", "Components", "Pages"],
              "Tenants",
              "Tenant call specs",
              "Calls",
              "Call details",
              "Onboarding",
              "Services",
              "Call spec editor",
            ],
          ],
        ],
      },
    },
  },
};

export default preview;
