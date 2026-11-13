import { Check, Copy } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { Button } from "./Button";

export function TelnyxWebhookField({ url }: { url: string }) {
  const id = useId();
  const [state, setState] = useState<"idle" | "copied" | "error">("idle");
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => {
    if (resetTimer.current !== null) clearTimeout(resetTimer.current);
  }, []);
  async function copy() {
    if (resetTimer.current !== null) clearTimeout(resetTimer.current);
    try {
      await navigator.clipboard.writeText(url);
      setState("copied");
      resetTimer.current = setTimeout(() => setState("idle"), 2000);
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
          <span aria-live="polite">{state === "copied" ? "Copied" : "Copy"}</span>
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
        Configure this URL in Telnyx for the Voice API Application
      </p>
      {state === "error" ? (
        <p role="status">
          Copy failed. Select the URL and copy it manually.
        </p>
      ) : null}
    </div>
  );
}
