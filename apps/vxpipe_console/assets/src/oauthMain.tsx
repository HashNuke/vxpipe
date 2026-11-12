import "./fonts.css";
import { createRoot } from "react-dom/client";
import { OAuthConsent, type Consent } from "./admin/authentication/OAuthConsent";
import { OAuthUnavailable } from "./admin/authentication/OAuthUnavailable";

const root = document.getElementById("oauth-root");
if (!root) throw new Error("Missing authorization page");
if (root.dataset.state === "unavailable") {
  createRoot(root).render(<OAuthUnavailable />);
} else if ((root.dataset.state === "allowed" || root.dataset.state === "denied") && root.dataset.completion && root.dataset.consent) {
  const completion = JSON.parse(root.dataset.completion) as { callback: string; expires_at: string | null };
  const consent = JSON.parse(root.dataset.consent) as Consent;
  delete root.dataset.completion;
  createRoot(root).render(<OAuthConsent consent={consent} requestId={root.dataset.requestId!} csrfToken=""
    step={root.dataset.state} callbackUrl={completion.callback} expiresAt={completion.expires_at ?? undefined} />);
} else {
  if (!root.dataset.consent || !root.dataset.requestId || !root.dataset.csrfToken) {
    throw new Error("Missing authorization request");
  }
  const consent = JSON.parse(root.dataset.consent) as Consent;
  createRoot(root).render(<OAuthConsent consent={consent} requestId={root.dataset.requestId} csrfToken={root.dataset.csrfToken} />);
}
