import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { ConsoleNavigation } from "./admin/navigation/ConsoleNavigation";

// The island owns only navigation. LiveView retains ownership of its server DOM.
const root = document.getElementById("console-navigation");
const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;
if (root && csrfToken) {
  createRoot(root).render(<BrowserRouter><ConsoleNavigation csrfToken={csrfToken} external><></></ConsoleNavigation></BrowserRouter>);
}
