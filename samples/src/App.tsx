import { ConsoleTemplate } from "@pipecat-ai/voice-ui-kit";

const DEFAULT_OFFER_URL = "/api/rtvi/offer";

function offerUrl(): string {
  return import.meta.env.VITE_VXPIPE_RTVI_OFFER_URL?.trim() || DEFAULT_OFFER_URL;
}

export default function App() {
  return (
    <main className="sample-shell">
      <ConsoleTemplate
        transportType="smallwebrtc"
        connectParams={{ webrtcUrl: offerUrl() }}
        titleText="Vxpipe RTVI Playground"
        noBotVideo
      />
    </main>
  );
}
