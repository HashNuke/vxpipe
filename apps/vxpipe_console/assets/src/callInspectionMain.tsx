import { createRoot } from "react-dom/client";

import "@vxpipe/react/styles.css";
import "./callInspectionHost.css";
import { CallInspectionApp } from "./CallInspectionApp";

const root = document.getElementById("call-console-root");
const callId = root?.dataset.callId;
const tenantKey = root?.dataset.tenantKey;

if (!root || !callId || !tenantKey) {
  throw new Error("Missing call console host data");
}

createRoot(root).render(
  <CallInspectionApp tenantKey={tenantKey} callId={callId} />,
);
