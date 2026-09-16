import { useId, useState, type KeyboardEvent } from "react";
import type { VxpipeClient } from "@vxpipe/core";
import { Icon } from "./Icon.js";

export function Composer({
  client,
  disabled,
}: {
  client: VxpipeClient;
  disabled: boolean;
}) {
  const id = useId();
  const [draft, setDraft] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const send = async () => {
    if (pending || disabled || !draft.trim()) return;
    setPending(true);
    setError("");
    try {
      await client.sendText(draft.trim());
      setDraft("");
    } catch {
      setError(
        "Message wasn't sent. Your draft is here; try again when connected.",
      );
    } finally {
      setPending(false);
    }
  };
  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (
      event.key === "Enter" &&
      !event.shiftKey &&
      !event.nativeEvent.isComposing
    ) {
      event.preventDefault();
      void send();
    }
  };
  return (
    <div className="vx-composer">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void send();
        }}
      >
        <label className="vx-sr-only" htmlFor={id}>
          Message
        </label>
        <textarea
          id={id}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={onKeyDown}
          placeholder={
            disabled
              ? "Start a call to send a message"
              : "Type a message, or speak…"
          }
          disabled={disabled || pending}
          rows={2}
        />
        <div className="vx-composer-actions">
          <span>
            Enter to send <span aria-hidden="true">·</span> Shift + Enter for a
            new line
          </span>
          <button
            className="vx-button vx-primary"
            type="submit"
            aria-label="Send message"
            disabled={disabled || pending || !draft.trim()}
          >
            <Icon name="send" />
            {pending ? "Sending" : "Send"}
          </button>
        </div>
      </form>
      {error && (
        <p className="vx-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
