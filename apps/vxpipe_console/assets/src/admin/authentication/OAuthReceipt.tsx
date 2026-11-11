import { useEffect, useRef } from "react";
import { OAuthConsent, type Consent } from "./OAuthConsent";
import { deliverCallback, type OAuthCompletion } from "./oauthReceiptTransport";

export function OAuthReceipt({ consent, completion, state }: {
  consent: Consent;
  completion: OAuthCompletion;
  state: "allowed" | "denied";
}) {
  const delivered = useRef(false);
  useEffect(() => {
    if (!delivered.current) {
      delivered.current = true;
      deliverCallback(completion);
    }
  }, [completion]);

  return <OAuthConsent consent={consent} requestId={completion.request_id} csrfToken=""
    step={state} expiresAt={completion.expires_at ?? undefined} />;
}
