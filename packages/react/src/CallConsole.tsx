import { useState, useSyncExternalStore, type CSSProperties } from "react";
import type {
  CallConsoleController,
  CallDetailsSnapshot,
  LocalSessionSnapshot,
} from "@vxpipe/core";
import { PhoneCall, PhoneOff } from "lucide-react";
import { Participants } from "./Participants.js";
import { ParticipantDetails } from "./ParticipantDetails.js";
import { Conversation } from "./Conversation.js";
import { Composer } from "./Composer.js";
import { DeviceControls } from "./DeviceControls.js";
import { Metrics } from "./Metrics.js";
import type { ConsoleSnapshot } from "./types.js";
import { Variables } from "./Variables.js";

type Tab = "chat" | "variables" | "metrics" | "participants";

const detachedSession: LocalSessionSnapshot = {
  connectionState: "ready",
  alignment: "unavailable",
  microphone: "off",
  speakerMuted: false,
  inputDevice: "",
  outputDevice: "",
  devices: { inputs: [], outputs: [], outputSelection: false },
};
const subscribeDetached = () => () => undefined;
const getDetachedSession = () => detachedSession;

function formatDuration(durationMs: number | null) {
  const seconds = Math.max(0, Math.floor((durationMs ?? 0) / 1_000));
  const minutes = Math.floor(seconds / 60);
  return `${String(minutes).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function consoleSnapshot(
  details: CallDetailsSnapshot,
  local: LocalSessionSnapshot,
  attached: boolean,
): ConsoleSnapshot {
  const messages = [];
  const activities = [];
  const toolCalls = [];
  const events = [];
  for (const entity of details.timeline) {
    if (entity.kind === "message") messages.push(entity.value);
    if (entity.kind === "activity") activities.push(entity.value);
    if (entity.kind === "tool-call") toolCalls.push(entity.value);
    if (entity.kind === "protocol-event") events.push(entity.value);
  }
  const state =
    details.call.state === "failed" || local.connectionState === "failed"
      ? "failed"
      : details.call.state === "ended"
        ? "ended"
        : attached && local.connectionState === "connected"
          ? "connected"
          : "ready";
  const alignment = attached
    ? local.alignment
    : messages.some((message) => message.spokenRange)
      ? "word"
      : "unavailable";

  return {
    callId: details.call.id,
    state,
    duration: formatDuration(details.call.durationMs),
    participants: details.participants.map((participant) => participant.value),
    messages,
    activities,
    toolCalls,
    events,
    metrics: details.metrics.map((metric) => metric.value),
    metricsEnabled: details.metrics.length > 0,
    variables:
      details.variables.state === "available" ? details.variables.value : null,
    alignment,
    microphone: local.microphone,
    speakerMuted: local.speakerMuted,
    inputDevice: local.inputDevice,
    outputDevice: local.outputDevice,
    devices: local.devices,
    notice: local.notice,
  };
}

function defaultParticipantId(snapshot: ConsoleSnapshot) {
  return (
    snapshot.participants.find((participant) => participant.role === "agent")?.id ??
    snapshot.participants[0]?.id ??
    null
  );
}

export interface CallConsoleProps {
  controller: CallConsoleController;
  initialTab?: Tab;
  theme?: "light" | "dark";
  maxHeight?: CSSProperties["maxHeight"];
}

export function CallConsole({
  controller,
  initialTab = "chat",
  theme = "dark",
  maxHeight,
}: CallConsoleProps) {
  const details = useSyncExternalStore(
    controller.details.subscribe,
    controller.details.getSnapshot,
    controller.details.getSnapshot,
  );
  const live = controller.live;
  const local = useSyncExternalStore(
    live?.subscribe ?? subscribeDetached,
    live?.getSnapshot ?? getDetachedSession,
    live?.getSnapshot ?? getDetachedSession,
  );
  const snapshot = consoleSnapshot(details, local, live !== undefined);
  const [tab, setTab] = useState<Tab>(initialTab);
  const [selectedParticipantId, setSelectedParticipantId] = useState<string | null>(
    defaultParticipantId(snapshot),
  );
  const [runRevision, setRunRevision] = useState(0);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const connected = live !== undefined && local.connectionState === "connected";
  const ended = details.call.state === "ended" || details.call.state === "failed";
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
    if (!live) return;
    setError("");
    setPending(true);
    try {
      if (connected) await live.disconnect();
      else {
        await live.connect();
        if (ended) {
          const nextDetails = controller.details.getSnapshot();
          const nextSnapshot = consoleSnapshot(
            nextDetails,
            live.getSnapshot(),
            true,
          );
          setTab("chat");
          setSelectedParticipantId(defaultParticipantId(nextSnapshot));
          setRunRevision((revision) => revision + 1);
        }
      }
    } catch {
      setError(
        "Couldn't change the call connection. Check its status before trying again.",
      );
    } finally {
      setPending(false);
    }
  };
  const status = connected
    ? "Connected"
    : details.call.state === "ended"
      ? "Call ended"
      : details.call.state === "failed"
        ? "Connection failed"
        : details.call.state === "running"
          ? "In progress"
          : "Ready";

  return (
    <div className="vx-console" data-vx-theme={theme} style={{ maxHeight }}>
      <header className="vx-call-header">
        {live && (
          <DeviceControls snapshot={snapshot} controls={live} theme={theme} />
        )}
        <div className="vx-call-actions">
          {live && (
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
                  : ended
                    ? "Call"
                    : "Start call"}
            </button>
          )}
          <div className="vx-call-action-meta">
            <span className={`vx-call-state vx-state-${snapshot.state}`}>
              <i />
              {status}
            </span>
            <time>{snapshot.duration}</time>
          </div>
        </div>
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
      <div className="vx-workspace" key={runRevision}>
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
          {tab === "chat" && live && (
            <Composer controls={live} disabled={!connected} />
          )}
        </main>
      </div>
    </div>
  );
}
