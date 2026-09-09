import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import { superviseVite } from "./vite-dev-lifecycle.mjs";

test("closes Vite exactly once when its Phoenix parent closes stdin", async () => {
  const input = new EventEmitter();
  const signals = new EventEmitter();
  const calls = [];

  input.resume = () => calls.push("resume");

  const server = {
    close: async () => calls.push("close"),
    listen: async () => calls.push("listen"),
    printUrls: () => calls.push("print-urls"),
  };

  const lifecycle = await superviseVite({
    createServer: async () => server,
    exit: (code) => calls.push(["exit", code]),
    input,
    signals,
  });

  input.emit("end");
  signals.emit("SIGTERM");
  await lifecycle.done;

  assert.deepEqual(calls, [
    "listen",
    "print-urls",
    "resume",
    "close",
    ["exit", 0],
  ]);
});
