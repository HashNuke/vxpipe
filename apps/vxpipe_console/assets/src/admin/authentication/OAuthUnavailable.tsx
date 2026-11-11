import { ArrowRight, CircleSlash } from "lucide-react";
import { Button } from "../Button";
import type { Theme } from "./types";
import "./oauthConsent.css";

export function OAuthUnavailable({ clientName, theme = "dark", onBack }: {
  clientName?: string;
  theme?: Theme;
  onBack?: () => void;
}) {
  return <div className="vx-admin oauth-preview" data-theme={theme}>
    <header className="oauth-preview-header">
      <span className="oauth-preview-wordmark">Vxpipe</span>
      <span>MCP connection</span>
    </header>
    <main className="oauth-preview-main">
      <CircleSlash size={32} className="oauth-preview-status" aria-hidden />
      <h1>This request can’t be completed</h1>
      <p className="oauth-preview-lead">The request may have expired or already been used. Start a new connection from {clientName ?? "your client"}.</p>
      <div className="oauth-preview-outcome-actions">
        <Button asChild>
          <a href="/" onClick={onBack ? (event) => { event.preventDefault(); onBack(); } : undefined}>
            Back to Vxpipe <ArrowRight size={16} aria-hidden />
          </a>
        </Button>
      </div>
    </main>
  </div>;
}
