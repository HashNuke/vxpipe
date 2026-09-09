import { createServer } from "vite";

import { superviseVite } from "./vite-dev-lifecycle.mjs";

await superviseVite({
  createServer,
  exit: (code) => process.exit(code),
  input: process.stdin,
  signals: process,
});
