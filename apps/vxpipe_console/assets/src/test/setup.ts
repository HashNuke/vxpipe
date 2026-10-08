import "@testing-library/jest-dom/vitest";
import { setTimeout as settleTimers } from "node:timers/promises";
import { afterAll } from "vitest";

// Radix focus scopes defer unmount events. Keep this file's jsdom realm alive
// until that queued cleanup finishes, before the worker loads another file.
afterAll(() => settleTimers(0));

class TestResizeObserver implements ResizeObserver {
  disconnect() {}
  observe() {}
  unobserve() {}
}

globalThis.ResizeObserver = TestResizeObserver;
Element.prototype.scrollIntoView = () => {};
