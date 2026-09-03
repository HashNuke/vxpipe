import { useState } from "react";

export type RoomSnapshot = {
  room_id: string;
  incarnation_id: string;
  tenant_id: string;
  created_by_actor_id: string;
  lifecycle: string;
};

type RoomResponse = {
  room: RoomSnapshot;
};

type ParticipantSnapshot = {
  participant_id: string;
  role: string;
  room_id: string;
  state: string;
};

type GatewaySession = {
  session_id: string;
  expires_at: string;
  transport: {
    type: "smallwebrtc";
    endpoint: string;
    request_data: { session_id: string };
  };
};

type SessionResponse = {
  participant: ParticipantSnapshot;
  session: GatewaySession;
};

export type RoomConnection = {
  room: RoomSnapshot;
  participant: ParticipantSnapshot;
  session: GatewaySession;
};

type CreateRoomPageProps = {
  onCreated: (connection: RoomConnection) => void;
};

function isRoomResponse(value: unknown): value is RoomResponse {
  if (!value || typeof value !== "object" || !("room" in value)) {
    return false;
  }

  const room = value.room;

  return (
    !!room &&
    typeof room === "object" &&
    "room_id" in room &&
    typeof room.room_id === "string" &&
    "incarnation_id" in room &&
    typeof room.incarnation_id === "string"
  );
}

function isSessionResponse(value: unknown): value is SessionResponse {
  if (
    !value ||
    typeof value !== "object" ||
    !("participant" in value) ||
    !("session" in value)
  ) {
    return false;
  }

  const { participant, session } = value;

  return (
    !!participant &&
    typeof participant === "object" &&
    "participant_id" in participant &&
    typeof participant.participant_id === "string" &&
    !!session &&
    typeof session === "object" &&
    "session_id" in session &&
    typeof session.session_id === "string" &&
    "transport" in session &&
    !!session.transport &&
    typeof session.transport === "object" &&
    "type" in session.transport &&
    session.transport.type === "smallwebrtc" &&
    "endpoint" in session.transport &&
    typeof session.transport.endpoint === "string" &&
    "request_data" in session.transport &&
    !!session.transport.request_data &&
    typeof session.transport.request_data === "object" &&
    "session_id" in session.transport.request_data &&
    session.transport.request_data.session_id === session.session_id
  );
}

export default function CreateRoomPage({ onCreated }: CreateRoomPageProps) {
  const [roomId] = useState(() => `room_${crypto.randomUUID()}`);
  const [room, setRoom] = useState<RoomSnapshot>();
  const [error, setError] = useState<string>();
  const [creating, setCreating] = useState(false);

  async function createRoom() {
    setCreating(true);
    setError(undefined);

    try {
      let createdRoom = room;

      if (!createdRoom) {
        const response = await fetch("/api/rooms", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ room_id: roomId }),
        });

        if (!response.ok) {
          throw new Error("The gateway could not create a room.");
        }

        const payload: unknown = await response.json();

        if (!isRoomResponse(payload)) {
          throw new Error("The gateway returned an invalid room response.");
        }

        createdRoom = payload.room;
        setRoom(createdRoom);
      }

      const sessionResponse = await fetch(
        `/api/rooms/${encodeURIComponent(createdRoom.room_id)}/sessions`,
        { method: "POST" },
      );

      if (!sessionResponse.ok) {
        throw new Error("The gateway could not prepare a voice session.");
      }

      const sessionPayload: unknown = await sessionResponse.json();

      if (!isSessionResponse(sessionPayload)) {
        throw new Error("The gateway returned an invalid voice-session response.");
      }

      onCreated({ room: createdRoom, ...sessionPayload });
    } catch (reason) {
      const detail = reason instanceof Error ? reason.message : "Room creation failed.";
      setError(`${detail} Check that bin/dev is running, then try again.`);
    } finally {
      setCreating(false);
    }
  }

  return (
    <main className="create-room-page">
      <section className="create-room-content" aria-labelledby="create-room-title">
        <h1 id="create-room-title">Open a room in Vxpipe.</h1>
        <p>
          Create one supervised development room, then continue to the Pipecat voice console.
        </p>

        <button className="create-room-action" type="button" onClick={createRoom} disabled={creating}>
          <span>{creating ? "Creating room…" : "Create room"}</span>
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M5 12h13M13 6l6 6-6 6" />
          </svg>
        </button>

        {error ? <p className="create-room-error" role="alert">{error}</p> : null}
      </section>
    </main>
  );
}
