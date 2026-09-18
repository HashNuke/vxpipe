import { createRoot } from "react-dom/client";

import "@pipecat-ai/voice-ui-kit/styles";
import "./styles.css";
import PlaygroundApp from "./PlaygroundApp";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Missing #root element");
}

createRoot(root).render(<PlaygroundApp />);
