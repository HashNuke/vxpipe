import { useState } from "react";
import type {
  ActivityEvent,
  CallSnapshot,
  Message,
  ProtocolEvent,
  ToolCall,
} from "@vxpipe/core";
import {
  ChevronDown,
  CircleAlert,
  CircleCheck,
  LoaderCircle,
  Wrench,
} from "lucide-react";
import { Icon } from "./Icon.js";
import { TurnMetricsTooltip } from "./TurnMetricsTooltip.js";

type Filter = "messages" | "logs" | "events" | "tools";
type Filters = Record<Filter, boolean>;
const defaultFilters: Filters = {
  messages: true,
  logs: false,
  events: true,
  tools: true,
};
const filterLabels: Record<Filter, string> = {
  messages: "Messages",
  logs: "Logs",
  events: "Events",
  tools: "Tool calls",
};
const filterIcons = {
  messages: "message",
  logs: "log",
  events: "event",
} as const;

function MessageText({
  message,
  alignment,
}: {
  message: Message;
  alignment: CallSnapshot["alignment"];
}) {
  const range = alignment !== "unavailable" && message.spokenRange;
  if (
    !range ||
    range.start < 0 ||
    range.end > message.text.length ||
    range.end <= range.start
  )
    return <>{message.text}</>;
  return (
    <>
      {message.text.slice(0, range.start)}
      <mark>{message.text.slice(range.start, range.end)}</mark>
      {message.text.slice(range.end)}
    </>
  );
}

function MessageRow({
  message,
  snapshot,
  theme,
}: {
  message: Message;
  snapshot: CallSnapshot;
  theme: "light" | "dark";
}) {
  const person = snapshot.participants.find(
    (item) => item.id === message.participantId,
  );
  return (
    <article className={`vx-message vx-message-${person?.role ?? "unknown"}`}>
      <span className={`vx-avatar vx-${person?.role ?? "unknown"}`}>
        {person?.name.slice(0, 1) ?? "?"}
      </span>
      <div>
        <header>
          <strong>{person?.name ?? "Unknown speaker"}</strong>
          {message.state === "streaming" && (
            <span className="vx-streaming" role="img" aria-label="Streaming">
              <i />
              <i />
              <i />
            </span>
          )}
          {snapshot.metricsEnabled &&
            (message.metrics && message.metrics.length > 0 ? (
              <TurnMetricsTooltip
                metrics={message.metrics}
                speaker={person?.name ?? "Unknown speaker"}
                time={message.time}
                theme={theme}
              />
            ) : (
              <button
                className="vx-turn-metrics-button"
                aria-label={`Metrics unavailable for ${person?.name ?? "Unknown speaker"} at ${message.time}`}
                title="Metrics unavailable"
                disabled
              >
                <Icon name="metrics" />
              </button>
            ))}
          <time>{message.time}</time>
        </header>
        <p>
          <MessageText message={message} alignment={snapshot.alignment} />
        </p>
        {message.state === "interrupted" && (
          <small>Interrupted · some text may not have been spoken</small>
        )}
      </div>
    </article>
  );
}

function ActivityRow({ event }: { event: ActivityEvent }) {
  return (
    <div className="vx-timeline-activity">
      <Icon name="event" />
      <span>{event.text}</span>
      <time>{event.time}</time>
    </div>
  );
}

function ToolRow({ tool }: { tool: ToolCall }) {
  const [expanded, setExpanded] = useState(false);
  const hasDetails = tool.request !== undefined || tool.response !== undefined;
  const statusLabel =
    tool.status === "pending"
      ? "Pending"
      : tool.status === "completed"
        ? "Completed"
        : "Error";
  const StatusIcon =
    tool.status === "pending"
      ? LoaderCircle
      : tool.status === "completed"
        ? CircleCheck
        : CircleAlert;

  const summary = (
    <>
      <Wrench aria-hidden="true" />
      <strong>{tool.name}</strong>
      {hasDetails && (
        <ChevronDown className="vx-tool-chevron" aria-hidden="true" />
      )}
      <span
        className={`vx-tool-status vx-tool-${tool.status}`}
        role="img"
        aria-label={statusLabel}
        title={statusLabel}
      >
        <StatusIcon aria-hidden="true" />
      </span>
      <time>{tool.time}</time>
    </>
  );

  return (
    <div className="vx-timeline-tool">
      {hasDetails ? (
        <button
          className="vx-tool-summary"
          aria-expanded={expanded}
          aria-label={`${expanded ? "Hide" : "Show"} details for ${tool.name}`}
          onClick={() => setExpanded((current) => !current)}
        >
          {summary}
        </button>
      ) : (
        <div className="vx-tool-summary">{summary}</div>
      )}
      {hasDetails && expanded && (
        <div className="vx-tool-details">
          {tool.request !== undefined && (
            <section>
              <h3>Request</h3>
              <pre>{JSON.stringify(tool.request, null, 2)}</pre>
            </section>
          )}
          {tool.response !== undefined && (
            <section>
              <h3>Response</h3>
              <pre>{JSON.stringify(tool.response, null, 2)}</pre>
            </section>
          )}
        </div>
      )}
    </div>
  );
}

function LogRow({ event }: { event: ProtocolEvent }) {
  return (
    <details className="vx-timeline-log">
      <summary>
        <span className={`vx-direction vx-${event.direction}`}>
          {event.direction === "in" ? "RX" : "TX"}
        </span>
        <strong>{event.type}</strong>
        <span>{event.summary}</span>
        <time>{event.time}</time>
      </summary>
      <pre>{JSON.stringify(event.details, null, 2)}</pre>
    </details>
  );
}

type TimelineItem =
  | { kind: "messages"; id: string; time: string; value: Message }
  | { kind: "events"; id: string; time: string; value: ActivityEvent }
  | { kind: "tools"; id: string; time: string; value: ToolCall }
  | { kind: "logs"; id: string; time: string; value: ProtocolEvent };

function timeline(snapshot: CallSnapshot, filters: Filters): TimelineItem[] {
  const items: TimelineItem[] = [];
  if (filters.messages)
    items.push(
      ...snapshot.messages.map((value) => ({
        kind: "messages" as const,
        id: value.id,
        time: value.time,
        value,
      })),
    );
  if (filters.events)
    items.push(
      ...snapshot.activities.map((value) => ({
        kind: "events" as const,
        id: value.id,
        time: value.time,
        value,
      })),
    );
  if (filters.tools)
    items.push(
      ...snapshot.toolCalls.map((value) => ({
        kind: "tools" as const,
        id: value.id,
        time: value.time,
        value,
      })),
    );
  if (filters.logs)
    items.push(
      ...snapshot.events
        .filter((event) => event.protocol === "rtvi")
        .slice(-500)
        .map((value) => ({
          kind: "logs" as const,
          id: value.id,
          time: value.time,
          value,
        })),
    );
  return items.sort(
    (left, right) =>
      left.time.localeCompare(right.time) || left.id.localeCompare(right.id),
  );
}

export function Conversation({
  snapshot,
  theme = "dark",
}: {
  snapshot: CallSnapshot;
  theme?: "light" | "dark";
}) {
  const [filters, setFilters] = useState<Filters>(defaultFilters);
  const speaking = snapshot.participants.find(
    (person) => person.role === "agent" && person.state === "speaking",
  );
  const items = timeline(snapshot, filters);
  const toggle = (filter: Filter) =>
    setFilters((current) => ({ ...current, [filter]: !current[filter] }));

  return (
    <section className="vx-conversation" aria-label="Conversation">
      <div className="vx-timeline-filters" aria-label="Conversation filters">
        {(Object.keys(defaultFilters) as Filter[]).map((filter) => (
          <button
            key={filter}
            className={filters[filter] ? "vx-filter-active" : ""}
            aria-pressed={filters[filter]}
            aria-label={`${filters[filter] ? "Hide" : "Show"} ${filterLabels[filter]}`}
            title={filterLabels[filter]}
            onClick={() => toggle(filter)}
          >
            {filter === "tools" ? (
              <Wrench aria-hidden="true" />
            ) : (
              <Icon name={filterIcons[filter]} />
            )}
            <span>{filterLabels[filter]}</span>
          </button>
        ))}
        <button
          className="vx-filter-reset"
          aria-label="Reset filters"
          title="Reset filters"
          onClick={() => setFilters({ ...defaultFilters })}
        >
          <Icon name="reset" />
          <span>Reset</span>
        </button>
      </div>
      <div className="vx-transcript">
        {items.length === 0 && (
          <div className="vx-empty">
            <h2>
              {snapshot.state === "connected"
                ? "No conversation items"
                : "No call active"}
            </h2>
          </div>
        )}
        {items.map((item) => {
          if (item.kind === "messages")
            return (
              <MessageRow
                key={`message-${item.id}`}
                message={item.value}
                snapshot={snapshot}
                theme={theme}
              />
            );
          if (item.kind === "events")
            return <ActivityRow key={`event-${item.id}`} event={item.value} />;
          if (item.kind === "tools")
            return <ToolRow key={`tool-${item.id}`} tool={item.value} />;
          return <LogRow key={`log-${item.id}`} event={item.value} />;
        })}
      </div>
      {speaking && (
        <div className="vx-speaking" role="status">
          <div className="vx-audio-bars" aria-hidden="true">
            {[8, 17, 12, 23, 14, 20, 8].map((height, i) => (
              <i key={i} style={{ height }} />
            ))}
          </div>
          <strong>{speaking.name} is speaking</strong>
          <span>
            {snapshot.alignment === "unavailable"
              ? "Word timing unavailable"
              : `${snapshot.alignment === "word" ? "Word" : "Segment"} timing available`}
          </span>
        </div>
      )}
    </section>
  );
}
