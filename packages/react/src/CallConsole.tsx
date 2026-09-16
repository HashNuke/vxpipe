import { useState, useSyncExternalStore, type CSSProperties } from "react";
import type { VxpipeClient } from "@vxpipe/core";
import { PhoneCall, PhoneOff } from "lucide-react";
import { Participants } from "./Participants.js";
import { ParticipantDetails } from "./ParticipantDetails.js";
import { Conversation } from "./Conversation.js";
import { Composer } from "./Composer.js";
import { DeviceControls } from "./DeviceControls.js";
import { Metrics } from "./Metrics.js";
import { Variables } from "./Variables.js";

type Tab = "chat" | "variables" | "metrics" | "participants";
export interface CallConsoleProps {
  client: VxpipeClient;
  initialTab?: Tab;
  theme?: "light" | "dark";
  maxHeight?: CSSProperties["maxHeight"];
}

export function CallConsole({
  client,
  initialTab = "chat",
  theme = "dark",
  maxHeight,
}: CallConsoleProps) {
  const snapshot = useSyncExternalStore(
    client.subscribe,
    client.getSnapshot,
    client.getSnapshot,
  );
  const [tab, setTab] = useState<Tab>(initialTab);
  const [selectedParticipantId, setSelectedParticipantId] = useState<string | null>(
    snapshot.participants.find((participant) => participant.role === "agent")?.id ??
      snapshot.participants[0]?.id ??
      null,
  );
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const connected = snapshot.state === "connected";
  const ended = snapshot.state === "ended" || snapshot.state === "failed";
  const selectedParticipant =
    snapshot.participants.find(
      (participant) => participant.id === selectedParticipantId,
    ) ??
    snapshot.participants[0] ??
    null;
  const selectParticipant = (participantId: string) => {
    setSelectedParticipantId(participantId);
    setTab("participants");
  };
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
    <div
      className="vx-console"
      data-vx-theme={theme}
      style={{ maxHeight }}
    >
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
              {connected ? (
                <PhoneOff aria-hidden="true" />
              ) : (
                <PhoneCall aria-hidden="true" />
              )}
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
        <Participants
          participants={snapshot.participants}
          selectedParticipantId={selectedParticipant?.id ?? null}
          onSelect={selectParticipant}
        />
        <main className="vx-main">
          <nav className="vx-tabs" aria-label="Call views">
            {(["chat", "variables", "metrics", "participants"] as const).map((item) => (
              <button
                className={tab === item ? "vx-tab-active" : ""}
                aria-current={tab === item ? "page" : undefined}
                key={item}
                onClick={() => setTab(item)}
              >
                {item === "chat"
                  ? "Conversation"
                  : item[0].toUpperCase() + item.slice(1)}
              </button>
            ))}
          </nav>
          {tab === "chat" && <Conversation snapshot={snapshot} theme={theme} />}
          {tab === "variables" && <Variables snapshot={snapshot.variables} />}
          {tab === "metrics" && <Metrics snapshot={snapshot} theme={theme} />}
          {tab === "participants" && (
            <ParticipantDetails participant={selectedParticipant} />
          )}
          {tab === "chat" && <Composer client={client} disabled={!connected} />}
        </main>
      </div>
    </div>
  );
}
