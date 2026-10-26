import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  define: { "import.meta.env.STORYBOOK_VXPIPE_VERSION": JSON.stringify(readFileSync(new URL("../../../VERSION", import.meta.url), "utf8").trim()) },
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
});
