import { useMemo, useState } from "react";
import { ConsoleTemplate } from "@pipecat-ai/voice-ui-kit";

import CreateRoomPage, { type RoomConnection } from "./CreateRoomPage";
import TransferPage from "./TransferPage";

const DEFAULT_OFFER_URL = "/api/rtvi/offer";

function offerUrl(sessionEndpoint: string): string {
  return sessionEndpoint || DEFAULT_OFFER_URL;
}

export default function App() {
  const [connection, setConnection] = useState<RoomConnection>();
  const clientOptions = useMemo(
    () => ({
      enableCam: false,
      enableMic: true,
      callbacks: {
        onDisconnected: () => setConnection(undefined),
      },
    }),
    [],
  );

  if (window.location.pathname === "/transfer") {
    return <TransferPage />;
  }

  if (!connection) {
    return <CreateRoomPage onCreated={setConnection} />;
  }

  return (
    <main className="console-page">
      <ConsoleTemplate
        key={connection.incarnationId}
        transportType="smallwebrtc"
        clientOptions={clientOptions}
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
