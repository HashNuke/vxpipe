import { Plug } from "lucide-react";
import { useState } from "react";

import cartesiaIcon from "./assets/icons/cartesia.svg";
import deepgramIcon from "./assets/icons/deepgram.ico";
import deepseekIcon from "./assets/icons/deepseek.ico";
import elevenlabsIcon from "./assets/icons/elevenlabs.svg";
import fireworksIcon from "./assets/icons/fireworks.svg";
import googleIcon from "./assets/icons/google-ai-studio.png";
import openaiIcon from "./assets/icons/openai.svg";
import openrouterIcon from "./assets/icons/openrouter.png";
import rimeIcon from "./assets/icons/rime.png";
import telnyxIcon from "./assets/icons/telnyx.png";
import twilioIcon from "./assets/icons/twilio.png";
import vertexAiIcon from "./assets/icons/vertex-ai.png";
import zenmuxIcon from "./assets/icons/zenmux.svg";
import type { ServiceProvider } from "./serviceTypes";

// Keep built-in integrations available without fetching icons from a directory.
const serviceFavicons: Record<ServiceProvider, string | null> = {
  cartesia: cartesiaIcon,
  deepgram: deepgramIcon,
  deepseek: deepseekIcon,
  elevenlabs: elevenlabsIcon,
  fireworks: fireworksIcon,
  google: googleIcon,
  morse_code_api: null,
  openai: openaiIcon,
  openrouter: openrouterIcon,
  rime: rimeIcon,
  telnyx: telnyxIcon,
  twilio: twilioIcon,
  vertex_ai: vertexAiIcon,
  zenmux: zenmuxIcon,
};

export function ServiceLogo({
  name,
  provider,
}: {
  name: string;
  provider: ServiceProvider;
}) {
  const [failedIcon, setFailedIcon] = useState<string | null>(null);
  const favicon = serviceFavicons[provider];
  const showFavicon = favicon !== null && failedIcon !== favicon;

  return (
    <span
      aria-label={`${name} service logo`}
      className={`service-logo service-logo--${provider}`}
      data-logo-source={showFavicon ? "official" : "placeholder"}
      role="img"
    >
      {showFavicon ? (
        <img
          alt=""
          className="service-logo-image"
          onError={() => setFailedIcon(favicon)}
          src={favicon}
        />
      ) : (
        <Plug aria-hidden="true" size={20} strokeWidth={1.5} />
      )}
    </span>
  );
}
