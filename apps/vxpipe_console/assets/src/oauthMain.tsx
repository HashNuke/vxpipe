import "./fonts.css";
import { createRoot } from "react-dom/client";
import { OAuthConsent, type Consent } from "./admin/authentication/OAuthConsent";
import { OAuthUnavailable } from "./admin/authentication/OAuthUnavailable";
import { OAuthReceipt } from "./admin/authentication/OAuthReceipt";
import type { OAuthCompletion } from "./admin/authentication/oauthReceiptTransport";

const root = document.getElementById("oauth-root");
if (!root) throw new Error("Missing authorization page");
if (root.dataset.state === "unavailable") {
  createRoot(root).render(<OAuthUnavailable />);
} else if ((root.dataset.state === "allowed" || root.dataset.state === "denied") && root.dataset.completion && root.dataset.consent) {
  const completion = JSON.parse(root.dataset.completion) as OAuthCompletion;
  const consent = JSON.parse(root.dataset.consent) as Consent;
  delete root.dataset.completion;
  createRoot(root).render(<OAuthReceipt consent={consent} completion={completion} state={root.dataset.state} />);
} else {
  if (!root.dataset.consent || !root.dataset.requestId || !root.dataset.csrfToken) {
    throw new Error("Missing authorization request");
  }
  const consent = JSON.parse(root.dataset.consent) as Consent;
  createRoot(root).render(<OAuthConsent consent={consent} requestId={root.dataset.requestId} csrfToken={root.dataset.csrfToken} />);
}
