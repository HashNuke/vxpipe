import { useId, useState } from "react";
import type {
  ActivityEvent,
  Message,
  ProtocolEvent,
  ToolCall,
} from "@vxpipe/core";
import type { ConsoleSnapshot } from "./types.js";
import {
  ChevronDown,
  CircleAlert,
  CircleCheck,
  LoaderCircle,
  Wrench,
} from "lucide-react";
import { Icon } from "./Icon.js";
import type { ConversationFilters } from "./conversationFilters.js";
import {
  formatTimelineClock,
  TimelineTimestamp,
} from "./TimelineTimestamp.js";
import { TurnMetricsTooltip } from "./TurnMetricsTooltip.js";
import { participantDisplayName } from "./participantDisplayName.js";

function MessageText({
  message,
  alignment,
}: {
  message: Message;
  alignment: ConsoleSnapshot["alignment"];
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
  onSelectParticipant,
}: {
  message: Message;
  snapshot: ConsoleSnapshot;
  theme: "light" | "dark";
  onSelectParticipant?: (participantId: string) => void;
}) {
  const person = snapshot.participants.find(
    (item) => item.id === message.participantId,
  );
  const displayName = person ? participantDisplayName(person) : "Unknown speaker";
  const selectParticipant = person
    ? () => onSelectParticipant?.(person.id)
    : undefined;
  return (
    <article className={`vx-message vx-message-${person?.role ?? "unknown"}`}>
      {person && onSelectParticipant ? (
        <button
          aria-label={`Open ${displayName} participant`}
          className="vx-message-participant vx-message-avatar"
          onClick={selectParticipant}
        >
          <span className={`vx-avatar vx-${person.role}`}>
            {displayName.slice(0, 1)}
          </span>
        </button>
      ) : (
        <span className={`vx-avatar vx-${person?.role ?? "unknown"}`}>
          {displayName.slice(0, 1)}
        </span>
      )}
      <div>
        <header>
          {person && onSelectParticipant ? (
            <button
              aria-label={`Open ${displayName} participant`}
              className="vx-message-participant vx-message-name"
              onClick={selectParticipant}
            >
              {displayName}
            </button>
          ) : (
            <strong>{displayName}</strong>
          )}
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
                time={formatTimelineClock(message.occurredAt)}
                theme={theme}
              />
            ) : (
              <button
                className="vx-turn-metrics-button"
                aria-label={`Metrics unavailable for ${person?.name ?? "Unknown speaker"} at ${formatTimelineClock(message.occurredAt)}`}
                title="Metrics unavailable"
                disabled
              >
                <Icon name="metrics" />
              </button>
            ))}
          <TimelineTimestamp occurredAt={message.occurredAt} theme={theme} />
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

function ActivityRow({
  event,
  theme,
}: {
  event: ActivityEvent;
  theme: "light" | "dark";
}) {
  return (
    <div className="vx-timeline-activity">
      <Icon name="event" />
      <span>{event.text}</span>
      <TimelineTimestamp occurredAt={event.occurredAt} theme={theme} />
    </div>
  );
}

function ToolRow({
  tool,
  theme,
}: {
  tool: ToolCall;
  theme: "light" | "dark";
}) {
  const [expanded, setExpanded] = useState(false);
  const requestAvailable = tool.request !== undefined;
  const responseAvailable =
    tool.response !== undefined || tool.responseStatus !== undefined;
  const hasDetails = requestAvailable || responseAvailable;
  const [detail, setDetail] = useState<"request" | "response">(
    requestAvailable ? "request" : "response",
  );
  const detailsId = useId();
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
      <TimelineTimestamp occurredAt={tool.occurredAt} theme={theme} />
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
          <div className="vx-tool-detail-tabs" role="tablist" aria-label={`${tool.name} details`}>
            {requestAvailable && (
              <button
                id={`${detailsId}-request-tab`}
                role="tab"
                aria-selected={detail === "request"}
                aria-controls={`${detailsId}-panel`}
                onClick={() => setDetail("request")}
              >
                Request
              </button>
            )}
            {responseAvailable && (
              <button
                id={`${detailsId}-response-tab`}
                role="tab"
                aria-label="Response"
                aria-selected={detail === "response"}
                aria-controls={`${detailsId}-panel`}
                onClick={() => setDetail("response")}
              >
                Response
                {tool.responseStatus !== undefined && (
                  <span
                    className={`vx-tool-http-status ${
                      tool.responseStatus >= 200 && tool.responseStatus < 400
                        ? "vx-tool-http-success"
                        : tool.responseStatus >= 400
                          ? "vx-tool-http-error"
                          : ""
                    }`}
                    aria-hidden="true"
                    title={`HTTP ${tool.responseStatus}`}
                  >
                    {tool.responseStatus}
                  </span>
                )}
              </button>
            )}
          </div>
          <section
            id={`${detailsId}-panel`}
            role="tabpanel"
            aria-labelledby={`${detailsId}-${detail}-tab`}
          >
            {detail === "request" &&
              (tool.request === null ? (
                <p className="vx-tool-empty">No request arguments.</p>
              ) : (
                <pre>{JSON.stringify(tool.request, null, 2)}</pre>
              ))}
            {detail === "response" &&
              (tool.response === null || tool.response === undefined ? (
                <p className="vx-tool-empty">No response body.</p>
              ) : (
                <pre>{JSON.stringify(tool.response, null, 2)}</pre>
              ))}
          </section>
        </div>
      )}
    </div>
  );
}

function LogRow({
  event,
  theme,
}: {
  event: ProtocolEvent;
  theme: "light" | "dark";
}) {
  return (
    <details className="vx-timeline-log">
      <summary>
        <span className={`vx-direction vx-${event.direction}`}>
          {event.direction === "in" ? "RX" : "TX"}
        </span>
        <strong>{event.type}</strong>
        <span>{event.summary}</span>
        <TimelineTimestamp occurredAt={event.occurredAt} theme={theme} />
      </summary>
      <pre>{JSON.stringify(event.details, null, 2)}</pre>
    </details>
  );
}

type TimelineItem =
  | { kind: "messages"; id: string; occurredAt: string; value: Message }
  | { kind: "events"; id: string; occurredAt: string; value: ActivityEvent }
  | { kind: "tools"; id: string; occurredAt: string; value: ToolCall }
  | { kind: "logs"; id: string; occurredAt: string; value: ProtocolEvent };

function timeline(
  snapshot: ConsoleSnapshot,
  filters: ConversationFilters,
): TimelineItem[] {
  const items: TimelineItem[] = [];
  if (filters.messages)
    items.push(
      ...snapshot.messages.map((value) => ({
        kind: "messages" as const,
        id: value.id,
        occurredAt: value.occurredAt,
        value,
      })),
    );
  if (filters.events)
    items.push(
      ...snapshot.activities.map((value) => ({
        kind: "events" as const,
        id: value.id,
        occurredAt: value.occurredAt,
        value,
      })),
    );
  if (filters.tools)
    items.push(
      ...snapshot.toolCalls.map((value) => ({
        kind: "tools" as const,
        id: value.id,
        occurredAt: value.occurredAt,
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
          occurredAt: value.occurredAt,
          value,
        })),
    );
  return items.sort(
    (left, right) =>
      left.occurredAt.localeCompare(right.occurredAt) ||
      left.id.localeCompare(right.id),
  );
}

export function Conversation({
  filters,
  snapshot,
  theme = "dark",
  onSelectParticipant,
}: {
  filters: ConversationFilters;
  snapshot: ConsoleSnapshot;
  theme?: "light" | "dark";
  onSelectParticipant?: (participantId: string) => void;
}) {
  const items = timeline(snapshot, filters);

  return (
    <section className="vx-conversation" aria-label="Conversation">
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
                onSelectParticipant={onSelectParticipant}
              />
            );
          if (item.kind === "events")
            return (
              <ActivityRow
                key={`event-${item.id}`}
                event={item.value}
                theme={theme}
              />
            );
          if (item.kind === "tools")
            return (
              <ToolRow key={`tool-${item.id}`} tool={item.value} theme={theme} />
            );
          return (
            <LogRow key={`log-${item.id}`} event={item.value} theme={theme} />
          );
        })}
      </div>
    </section>
  );
}
