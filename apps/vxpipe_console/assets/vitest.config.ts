import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  define: { "import.meta.env.STORYBOOK_VXPIPE_VERSION": JSON.stringify(readFileSync(new URL("../../../VERSION", import.meta.url), "utf8").trim()) },
  resolve: {
    dedupe: ["react", "react-dom"],
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      "lucide-react": fileURLToPath(import.meta.resolve("lucide-react")),
      "@floating-ui/react": fileURLToPath(import.meta.resolve("@floating-ui/react")),
    },
  },
  test: {
    server: { deps: { inline: ["@vxpipe/react", /^@floating-ui\//, "lucide-react"] } },
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
});
