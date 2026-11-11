import "./fonts.css";
import { createRoot } from "react-dom/client";
import { OAuthConsent, type Consent } from "./admin/authentication/OAuthConsent";

const root = document.getElementById("oauth-root");
if (!root?.dataset.consent || !root.dataset.requestId || !root.dataset.csrfToken) {
  throw new Error("Missing authorization request");
}
const consent = JSON.parse(root.dataset.consent) as Consent;
createRoot(root).render(<OAuthConsent consent={consent} requestId={root.dataset.requestId} csrfToken={root.dataset.csrfToken} />);
