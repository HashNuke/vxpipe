import { useEffect, useRef, useState } from "react";

import { claimSampleSession, requestSampleAdmission } from "./sampleAdmission";
import {
  openTransferConnection,
  type TransferConnection,
  type TransferControl,
  type TransferProgress,
} from "./transferConnection";

type Phase = "idle" | "connecting" | "briefing" | "ready" | "accepting" | "active" | "closed" | "error";

type EventEntry = {
  id: number;
  label: string;
};

const phaseCopy: Record<Phase, string> = {
  idle: "Desk offline",
  connecting: "Establishing private line",
  briefing: "Listen to the private briefing",
  ready: "Ready to accept transfer",
  accepting: "Preparing your connection",
  active: "Main room active",
  closed: "Connection closed",
  error: "Connection unavailable",
};

const blockerCopy: Record<TransferProgress["blockers"][number], string> = {
  speech_to_text: "transcription", text_to_speech: "voice", model_inference: "the assistant",
  tools: "tools", media: "audio", recording: "recording", room_services: "call services",
  other: "your connection",
};

function progressCopy(progress: TransferProgress): string {
  switch (progress.phase) {
    case "cue": return "Playing connection cue";
    case "releasing": return "Connecting to the caller";
    case "recovering": return "Restoring the caller’s connection";
    case "preparing": {
      const labels = [...new Set(progress.blockers.map((kind) => blockerCopy[kind]))];
      return labels.length ? `Preparing ${labels.join(", ")}` : phaseCopy.accepting;
    }
  }
}

export default function TransferPage() {
  const connection = useRef<TransferConnection | undefined>(undefined);
  const activeAttempt = useRef<string | undefined>(undefined);
  const accepting = useRef(false);
  const eventSequence = useRef(0);
  const [phase, setPhase] = useState<Phase>("idle");
  const [interrupted, setInterrupted] = useState(false);
  const [attemptId, setAttemptId] = useState<string>();
  const [error, setError] = useState<string>();
  const [events, setEvents] = useState<EventEntry[]>([]);
  const [progress, setProgress] = useState<TransferProgress>();

  useEffect(() => () => connection.current?.close(), []);

  function record(label: string) {
    eventSequence.current += 1;
    const entry = { id: eventSequence.current, label };
    setEvents((current) => [...current.slice(-4), entry]);
  }

  function handleControl(control: TransferControl) {
    switch (control.type) {
      case "preparation":
        activeAttempt.current = control.attemptId;
        setAttemptId(control.attemptId);
        setPhase("briefing");
        record("Private briefing opened");
        break;
      case "acceptance_ready":
        if (control.attemptId !== activeAttempt.current) return;
        setPhase((current) => current === "briefing" ? "ready" : current);
        record("Briefing complete; acceptance available");
        break;
      case "active":
        if (control.attemptId !== activeAttempt.current) return;
        accepting.current = false;
        setPhase("active");
        record("Main room media activated");
        break;
      case "progress":
        if (control.attemptId !== activeAttempt.current || !accepting.current) return;
        setProgress(control);
        record(`${progressCopy(control)} · ${(control.elapsedMs / 1000).toFixed(1)} s`);
        break;
      case "error":
        accepting.current = false;
        setError(control.message);
        setPhase("error");
        record("Transfer control rejected");
        break;
    }
  }

  async function connect() {
    connection.current?.close();
    connection.current = undefined;
    activeAttempt.current = undefined;
    accepting.current = false;
    setInterrupted(false);
    setProgress(undefined);
    setAttemptId(undefined);
    setPhase("connecting");
    setError(undefined);
    record("Requesting destination admission");

    try {
      const admission = await requestSampleAdmission("/admin/samples/transfers");

      if (!admission) {
        setError(
          "The transfer sample is disabled. Restart bin/dev, then create a new room in the caller console.",
        );
        setPhase("error");
        record("Transfer sample setup required");
        return;
      }

      const room = await claimSampleSession(admission);

      connection.current = await openTransferConnection(room.session, {
        onControl: handleControl,
        onClosed: () => {
          accepting.current = false;
          setInterrupted(false);
          setPhase("closed");
          record("Destination connection closed");
        },
        onInterrupted: (value) => {
          setInterrupted(value);
          record(value ? "Destination connection interrupted" : "Destination connection restored");
        },
      });

      record("Destination media connected");
    } catch (reason) {
      const detail = reason instanceof Error ? reason.message : "The destination could not connect.";
      setError(`${detail} Request a human transfer in the caller console, then try again.`);
      setPhase("error");
      record("Destination connection failed");
    }
  }

  function accept() {
    if (interrupted || phase !== "ready" || !attemptId || !connection.current) {
      return;
    }

    try {
      connection.current.accept(attemptId);
      accepting.current = true;
      setPhase("accepting");
      record("Destination accepted transfer");
    } catch (reason) {
      const detail = reason instanceof Error ? reason.message : "The transfer could not be accepted.";
      setError(detail);
      setPhase("error");
      record("Transfer acceptance failed");
    }
  }

  function disconnect() {
    accepting.current = false;
    setInterrupted(false);
    connection.current?.close();
    connection.current = undefined;
    activeAttempt.current = undefined;
    setPhase("closed");
  }

  return (
    <main className="transfer-page">
      <div className="transfer-shell">
        <header className="transfer-header">
          <a href="/admin/samples/pipecat-console" aria-label="Vxpipe caller sample">VX</a>
          <p>Human transfer desk</p>
        </header>

        <section className={`transfer-status transfer-status--${interrupted ? "closed" : phase}`} aria-label="Transfer status">
          <span aria-hidden="true" />
          <div>
            <p>Destination state</p>
            <strong role="status" aria-live="polite">
              {interrupted ? "Connection interrupted" : phase === "accepting" && progress ? progressCopy(progress) : phaseCopy[phase]}
            </strong>
          </div>
        </section>

        <div className="transfer-workbench">
          <section className="transfer-panel" aria-labelledby="transfer-title">
            <div>
              <h1 id="transfer-title">Take the handoff.</h1>
              <p>
                In the caller console, ask the agent for human support. Then connect this desk to
                hear the private briefing before you accept.
              </p>
            </div>

            {!interrupted && (phase === "briefing" || phase === "ready") ? (
              <button
                className="transfer-action"
                type="button"
                onClick={accept}
                disabled={phase !== "ready"}
              >
                Accept transfer
              </button>
            ) : interrupted || phase === "active" || phase === "accepting" ? (
              <button className="transfer-action transfer-action--quiet" type="button" onClick={disconnect}>
                Disconnect
              </button>
            ) : (
              <button
                className="transfer-action"
                type="button"
                onClick={connect}
                disabled={phase === "connecting"}
              >
                {phase === "connecting" ? "Connecting…" : "Connect transfer desk"}
              </button>
            )}

            {error ? <p className="transfer-error" role="alert">{error}</p> : null}
          </section>

          <section className="transfer-ledger" aria-labelledby="transfer-ledger-title">
            <h2 id="transfer-ledger-title">Control ledger</h2>
            {events.length > 0 ? (
              <ol>
                {events.map((event) => <li key={event.id}>{event.label}</li>)}
              </ol>
            ) : (
              <p>No transfer activity yet.</p>
            )}
          </section>
        </div>
      </div>
    </main>
  );
}
