import { Check, Copy } from "lucide-react";
import { useId, useState } from "react";
import { Button } from "./Button";

export function TelnyxWebhookField({ url }: { url: string }) {
  const id = useId();
  const [state, setState] = useState<"idle" | "copied" | "error">("idle");
  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setState("copied");
    } catch {
      setState("error");
    }
  }
  return (
    <div className="setup-webhook">
      <div className="setup-webhook-heading">
        <label htmlFor={id}>Webhook URL</label>
        <Button
          type="button"
          aria-label="Copy webhook URL"
          onClick={() => void copy()}
        >
          {state === "copied" ? (
            <Check aria-hidden="true" size={16} />
          ) : (
            <Copy aria-hidden="true" size={16} />
          )}
          {state === "copied" ? "Copied" : "Copy"}
        </Button>
      </div>
      <input
        id={id}
        value={url}
        type="text"
        readOnly
        spellCheck={false}
        onFocus={(event) => event.target.select()}
        aria-describedby={`${id}-hint`}
      />
      <p id={`${id}-hint`}>
        Use this URL in your Telnyx Voice API application to receive call
        events.
      </p>
      {state !== "idle" ? (
        <p role="status">
          {state === "copied"
            ? "Webhook URL copied."
            : "Copy failed. Select the URL and copy it manually."}
        </p>
      ) : null}
    </div>
  );
}
