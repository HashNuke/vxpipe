import GoogleColor from "@lobehub/icons/es/Google/components/Color";
import ZenMuxMono from "@lobehub/icons/es/ZenMux/components/Mono";
import { useState } from "react";

import googleLogo from "./assets/icons/google.png";
import telnyxLogo from "./assets/icons/telnyx-green.png";
import vertexAiLogo from "./assets/icons/vertex-ai.svg";
import type { ServiceProvider } from "./serviceTypes";

const serviceMarks: Record<ServiceProvider, string> = {
  rime: "R",
  google: "G",
  openai: "O",
  vertex_ai: "V",
  zenmux: "Z",
  deepgram: "D",
  telnyx: "T",
  twilio: "T",
};

type LogoSource = "lobehub" | "official" | "avatar";

const logoSources: Record<ServiceProvider, LogoSource> = {
  rime: "avatar",
  google: "official",
  openai: "avatar",
  vertex_ai: "official",
  zenmux: "lobehub",
  deepgram: "avatar",
  telnyx: "official",
  twilio: "avatar",
};

const officialIconAssets: Partial<Record<ServiceProvider, string>> = {
  google: googleLogo,
  vertex_ai: vertexAiLogo,
  telnyx: telnyxLogo,
};

export function ServiceLogo({
  name,
  provider,
}: {
  name: string;
  provider: ServiceProvider;
}) {
  const [logoFailed, setLogoFailed] = useState(false);
  const source = logoSources[provider];
  const lobeLogo =
    source === "lobehub" ? (
      provider === "google" ? (
        <GoogleColor size="2rem" />
      ) : provider === "zenmux" ? (
        <ZenMuxMono size="2rem" />
      ) : null
    ) : null;
  const officialLogo =
    source === "official" && !logoFailed && officialIconAssets[provider] ? (
      <img
        alt=""
        className="service-logo-image service-logo-image--official"
        onError={() => setLogoFailed(true)}
        src={officialIconAssets[provider]}
      />
    ) : null;

  return (
    <span
      aria-label={`${name} service logo`}
      className={`service-logo service-logo--${provider}`}
      data-logo-source={source}
      role="img"
    >
      {lobeLogo ?? officialLogo ?? serviceMarks[provider]}
    </span>
  );
}
