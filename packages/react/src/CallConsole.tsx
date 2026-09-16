import { useState, useSyncExternalStore } from "react";
import type { VxpipeClient } from "@vxpipe/core";
import { Participants } from "./Participants.js";
import { Conversation } from "./Conversation.js";
import { Composer } from "./Composer.js";
import { DeviceControls } from "./DeviceControls.js";
import { Metrics } from "./Metrics.js";
import { Variables } from "./Variables.js";
import { Icon } from "./Icon.js";

type Tab = "chat" | "variables" | "metrics";
export interface CallConsoleProps {
  client: VxpipeClient;
  initialTab?: Tab;
  theme?: "light" | "dark";
}

export function CallConsole({
  client,
  initialTab = "chat",
  theme = "dark",
}: CallConsoleProps) {
  const snapshot = useSyncExternalStore(
    client.subscribe,
    client.getSnapshot,
    client.getSnapshot,
  );
  const [tab, setTab] = useState<Tab>(initialTab);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const connected = snapshot.state === "connected";
  const ended = snapshot.state === "ended" || snapshot.state === "failed";
  const act = async () => {
    setError("");
    setPending(true);
    try {
      if (connected) await client.disconnect();
      else await client.connect();
    } catch {
      setError(
        "Couldn't change the call connection. Check its status before trying again.",
      );
    } finally {
      setPending(false);
    }
  };
  return (
    <div className="vx-console" data-vx-theme={theme}>
      <header className="vx-call-header">
        <div className="vx-call-actions">
          <span className={`vx-call-state vx-state-${snapshot.state}`}>
            <i />
            {connected
              ? "Connected"
              : snapshot.state === "ended"
                ? "Call ended"
                : snapshot.state === "failed"
                  ? "Connection failed"
                  : "Ready"}
          </span>
          <time>{snapshot.duration}</time>
          {!ended && (
            <button
              className={`vx-button ${connected ? "vx-leave" : "vx-primary"}`}
              disabled={pending}
              onClick={() => void act()}
            >
              {connected && <Icon name="phone" />}
              {pending
                ? "Please wait"
                : connected
                  ? "Leave call"
                  : "Start call"}
            </button>
          )}
        </div>
        <DeviceControls snapshot={snapshot} client={client} theme={theme} />
      </header>
      {error && (
        <p className="vx-error vx-notice" role="alert">
          {error}
        </p>
      )}
      {snapshot.notice && (
        <p className="vx-notice" role="status">
          {snapshot.notice}
        </p>
      )}
      <div className="vx-workspace">
        <Participants participants={snapshot.participants} />
        <main className="vx-main">
          <nav className="vx-tabs" aria-label="Call views">
            {(["chat", "variables", "metrics"] as const).map((item) => (
              <button
                className={tab === item ? "vx-tab-active" : ""}
                aria-current={tab === item ? "page" : undefined}
                key={item}
                onClick={() => setTab(item)}
              >
                {item === "chat"
                  ? "Conversation"
                  : item === "variables"
                    ? "Variables"
                    : "Metrics"}
              </button>
            ))}
          </nav>
          {tab === "chat" && <Conversation snapshot={snapshot} theme={theme} />}
          {tab === "variables" && <Variables snapshot={snapshot.variables} />}
          {tab === "metrics" && <Metrics snapshot={snapshot} />}
          {tab === "chat" && <Composer client={client} disabled={!connected} />}
        </main>
      </div>
    </div>
  );
}
