import { useState } from "react";
import type { ProtocolEvent } from "@vxpipe/core";

export function EventLog({ events }: { events: readonly ProtocolEvent[] }) {
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<ProtocolEvent>();
  const [frozen, setFrozen] = useState<readonly ProtocolEvent[] | null>(null);
  const rtvi = (frozen ?? events).filter((event) => event.protocol === "rtvi");
  const visible = rtvi
    .slice(-500)
    .filter((event) =>
      `${event.type} ${event.summary}`
        .toLowerCase()
        .includes(query.toLowerCase()),
    );
  return (
    <section className="vx-event-log" aria-label="RTVI events">
      <div className="vx-panel-intro">
        <h2>
          RTVI events <span className="vx-count">{rtvi.length}</span>
        </h2>
        <p>Sent and received protocol events, including Vxpipe extensions.</p>
      </div>
      <div className="vx-log-tools">
        <input
          type="search"
          aria-label="Filter RTVI events"
          placeholder="Filter events…"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <button
          className="vx-button"
          aria-pressed={frozen !== null}
          onClick={() => setFrozen(frozen === null ? [...events] : null)}
        >
          {frozen === null ? "Pause feed" : "Resume feed"}
        </button>
      </div>
      <div className="vx-log-layout">
        <div className="vx-event-list">
          {visible.length === 0 && (
            <p className="vx-footnote">No matching RTVI events.</p>
          )}
          {visible.map((event) => (
            <button
              className={`vx-event-row ${selected?.id === event.id ? "vx-selected" : ""}`}
              key={event.id}
              onClick={() => setSelected(event)}
            >
              <time>{event.time}</time>
              <span className={`vx-direction vx-${event.direction}`}>
                {event.direction === "in" ? "RX" : "TX"}
              </span>
              <span>
                <strong>{event.type}</strong>
                <small>{event.summary}</small>
              </span>
            </button>
          ))}
        </div>
        <aside className="vx-event-detail" aria-label="Selected event">
          <h3>{selected ? selected.type : "Event details"}</h3>
          {selected ? (
            <>
              <p>
                {selected.direction === "in" ? "Received" : "Sent"} at{" "}
                {selected.time}
              </p>
              <pre>{JSON.stringify(selected.details, null, 2)}</pre>
            </>
          ) : (
            <p>Select an event to inspect its payload.</p>
          )}
        </aside>
      </div>
      {rtvi.length > 500 && (
        <p className="vx-footnote">
          Showing the latest 500 events. Older entries have been trimmed.
        </p>
      )}
    </section>
  );
}
