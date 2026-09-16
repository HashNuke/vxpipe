import "@testing-library/jest-dom/vitest";

if (!HTMLElement.prototype.scrollIntoView) {
  HTMLElement.prototype.scrollIntoView = () => {};
}
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";
afterEach(cleanup);
