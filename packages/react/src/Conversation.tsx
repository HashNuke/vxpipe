import type { CallSnapshot, Message } from "@vxpipe/core";

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

export function Conversation({ snapshot }: { snapshot: CallSnapshot }) {
  const speaking = snapshot.participants.find(
    (person) => person.role === "agent" && person.state === "speaking",
  );
  return (
    <section className="vx-conversation" aria-label="Conversation">
      <div className="vx-transcript">
        {snapshot.messages.length === 0 && (
          <div className="vx-empty">
            <h2>
              {snapshot.state === "connected"
                ? "No messages yet"
                : "No call active"}
            </h2>
          </div>
        )}
        {snapshot.messages.map((message) => {
          const person = snapshot.participants.find(
            (item) => item.id === message.participantId,
          );
          return (
            <article
              className={`vx-message vx-message-${person?.role ?? "unknown"}`}
              key={message.id}
            >
              <span className={`vx-avatar vx-${person?.role ?? "unknown"}`}>
                {person?.name.slice(0, 1) ?? "?"}
              </span>
              <div>
                <header>
                  <strong>{person?.name ?? "Unknown speaker"}</strong>
                  {message.state === "streaming" && (
                    <span
                      className="vx-streaming"
                      role="img"
                      aria-label="Streaming"
                    >
                      <i />
                      <i />
                      <i />
                    </span>
                  )}
                  <time>{message.time}</time>
                </header>
                <p>
                  <MessageText
                    message={message}
                    alignment={snapshot.alignment}
                  />
                </p>
                {message.state === "interrupted" && (
                  <small>
                    Interrupted · some text may not have been spoken
                  </small>
                )}
              </div>
            </article>
          );
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
