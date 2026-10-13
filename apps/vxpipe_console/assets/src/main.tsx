import { createRoot } from "react-dom/client";

import "@pipecat-ai/voice-ui-kit/styles";
import "./styles.css";
import { ConsoleNavigation } from "./admin/navigation/ConsoleNavigation";
import PlaygroundApp from "./PlaygroundApp";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Missing #root element");
}

const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;
if (!csrfToken) throw new Error("Missing CSRF token");
createRoot(root).render(<PlaygroundApp frame={children => <ConsoleNavigation csrfToken={csrfToken} crossDocument>{children}</ConsoleNavigation>} />);
