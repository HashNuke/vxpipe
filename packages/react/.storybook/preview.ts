import type { Preview } from "@storybook/react-vite";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/geist-mono/400.css";
import "../src/styles.css";
import "../stories/prototype.css";

const preview: Preview = {
  parameters: {
    layout: "fullscreen",
    options: { storySort: { order: ["Prototype", "Console"] } },
  },
};
export default preview;
