import { useEffect, useRef, useState } from "react";

import { claimSampleSession, requestSampleAdmission } from "./sampleAdmission";
import {
  openTransferConnection,
  type TransferConnection,
  type TransferControl,
} from "./transferConnection";

type Phase = "idle" | "connecting" | "briefing" | "accepting" | "active" | "closed" | "error";

type EventEntry = {
  id: number;
  label: string;
};

const phaseCopy: Record<Phase, string> = {
  idle: "Desk offline",
  connecting: "Establishing private line",
  briefing: "Private briefing line open",
  accepting: "Acceptance sent",
  active: "Main room active",
  closed: "Connection closed",
  error: "Connection unavailable",
};

export default function TransferPage() {
  const connection = useRef<TransferConnection | undefined>(undefined);
  const eventSequence = useRef(0);
  const [phase, setPhase] = useState<Phase>("idle");
  const [attemptId, setAttemptId] = useState<string>();
  const [error, setError] = useState<string>();
  const [events, setEvents] = useState<EventEntry[]>([]);

  useEffect(() => () => connection.current?.close(), []);

  function record(label: string) {
    eventSequence.current += 1;
    setEvents((current) => [...current.slice(-4), { id: eventSequence.current, label }]);
  }

  function handleControl(control: TransferControl) {
    switch (control.type) {
      case "preparation":
        setAttemptId(control.attemptId);
        setPhase("briefing");
        record("Private briefing opened");
        break;
      case "active":
        setPhase("active");
        record("Main room media activated");
        break;
      case "error":
        setError(control.message);
        setPhase("error");
        record("Transfer control rejected");
        break;
    }
  }

  async function connect() {
    connection.current?.close();
    connection.current = undefined;
    setPhase("connecting");
    setError(undefined);
    record("Requesting destination admission");

    try {
      const admission = await requestSampleAdmission("/sample/transfers");

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
          setPhase("closed");
          record("Destination connection closed");
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
    if (!attemptId || !connection.current) {
      return;
    }

    try {
      connection.current.accept(attemptId);
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
    connection.current?.close();
    connection.current = undefined;
    setPhase("closed");
  }

  return (
    <main className="transfer-page">
      <div className="transfer-shell">
        <header className="transfer-header">
          <a href="/pipecat-console" aria-label="Vxpipe caller sample">VX</a>
          <p>Human transfer desk</p>
        </header>

        <section className={`transfer-status transfer-status--${phase}`} aria-label="Transfer status">
          <span aria-hidden="true" />
          <div>
            <p>Destination state</p>
            <strong role="status" aria-live="polite">{phaseCopy[phase]}</strong>
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

            {phase === "briefing" ? (
              <button className="transfer-action" type="button" onClick={accept}>
                Accept transfer
              </button>
            ) : phase === "active" || phase === "accepting" ? (
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
