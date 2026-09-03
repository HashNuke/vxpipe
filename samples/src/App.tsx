import { useState } from "react";
import { ConsoleTemplate } from "@pipecat-ai/voice-ui-kit";

import CreateRoomPage, { type RoomSnapshot } from "./CreateRoomPage";

const DEFAULT_OFFER_URL = "/api/rtvi/offer";

function offerUrl(): string {
  return import.meta.env.VITE_VXPIPE_RTVI_OFFER_URL?.trim() || DEFAULT_OFFER_URL;
}

export default function App() {
  const [room, setRoom] = useState<RoomSnapshot>();

  if (!room) {
    return <CreateRoomPage onCreated={setRoom} />;
  }

  return (
    <main className="console-page">
      <ConsoleTemplate
        key={room.incarnation_id}
        transportType="smallwebrtc"
        connectParams={{ webrtcUrl: offerUrl() }}
        titleText="Vxpipe RTVI Playground"
        noBotVideo
      />
    </main>
  );
}
