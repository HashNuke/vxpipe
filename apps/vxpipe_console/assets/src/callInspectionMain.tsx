import { createRoot } from "react-dom/client";

import "@vxpipe/react/styles.css";
import "./callInspectionHost.css";
import { CallInspectionApp } from "./CallInspectionApp";

const root = document.getElementById("call-console-root");
const callId = root?.dataset.callId;

if (!root || !callId) {
  throw new Error("Missing call console host data");
}

createRoot(root).render(<CallInspectionApp callId={callId} />);
