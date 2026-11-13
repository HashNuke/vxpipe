import { useId } from "react";
import { CopyButton } from "./CopyButton";

export function TelnyxWebhookField({ url }: { url: string }) {
  const id = useId();
  return (
    <div className="setup-webhook">
      <div className="setup-webhook-heading">
        <label htmlFor={id}>Webhook URL</label>
        <CopyButton value={url} aria-label="Copy webhook URL"
          errorMessage="Copy failed. Select the URL and copy it manually." />
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
    </div>
  );
}
