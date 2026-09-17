import { createRoot } from "react-dom/client";

import { AdminApp } from "./AdminApp";

const root = document.getElementById("admin-root");

if (!root) {
  throw new Error("Missing #admin-root element");
}

const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;

if (!csrfToken) {
  throw new Error("Missing CSRF token");
}

createRoot(root).render(<AdminApp csrfToken={csrfToken} />);
