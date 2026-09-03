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

type CreateRoomPageProps = {
  onCreated: (room: RoomSnapshot) => void;
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

export default function CreateRoomPage({ onCreated }: CreateRoomPageProps) {
  const [roomId] = useState(() => `room_${crypto.randomUUID()}`);
  const [error, setError] = useState<string>();
  const [creating, setCreating] = useState(false);

  async function createRoom() {
    setCreating(true);
    setError(undefined);

    try {
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

      onCreated(payload.room);
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
