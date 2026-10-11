import { addons } from "storybook/manager-api";

addons.setConfig({
  sidebar: {
    // Keep the package slash in the label, since story titles use it for nesting.
    renderLabel: (item) =>
      item.id === "vxpipe-react" ? "@vxpipe/react" : item.name,
  },
});
