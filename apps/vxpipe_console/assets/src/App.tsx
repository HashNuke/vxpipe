import { useState } from "react";
import { ConsoleTemplate } from "@pipecat-ai/voice-ui-kit";

import CreateRoomPage, { type RoomConnection } from "./CreateRoomPage";

const DEFAULT_OFFER_URL = "/api/rtvi/offer";

function offerUrl(sessionEndpoint: string): string {
  return sessionEndpoint || DEFAULT_OFFER_URL;
}

export default function App() {
  const [connection, setConnection] = useState<RoomConnection>();

  if (!connection) {
    return <CreateRoomPage onCreated={setConnection} />;
  }

  return (
    <main className="console-page">
      <ConsoleTemplate
        key={connection.incarnationId}
        transportType="smallwebrtc"
        connectParams={{
          webrtcRequestParams: {
            endpoint: offerUrl(connection.session.transport.endpoint),
            requestData: connection.session.transport.request_data,
          },
        }}
        titleText="Vxpipe RTVI Playground"
        noBotVideo
      />
    </main>
  );
}
