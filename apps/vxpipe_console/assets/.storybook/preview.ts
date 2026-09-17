import type { Preview } from "@storybook/react-vite";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/geist-mono/400.css";
import "@vxpipe/react/styles.css";
import "../src/admin/admin.css";

const preview: Preview = {
  parameters: {
    layout: "fullscreen",
    options: {
      storySort: {
        order: [
          "Admin",
          [
            "Full journey",
            "Tenants",
            "Tenant definitions",
            "Definition calls",
            "Call details",
          ],
        ],
      },
    },
  },
};

export default preview;
