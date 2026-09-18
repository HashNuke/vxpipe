import { createRoot } from "react-dom/client";

import { App } from "./App";

const root = document.getElementById("admin-root");

if (!root) {
  throw new Error("Missing #admin-root element");
}

const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;

if (!csrfToken) {
  throw new Error("Missing CSRF token");
}

createRoot(root).render(<App csrfToken={csrfToken} />);
