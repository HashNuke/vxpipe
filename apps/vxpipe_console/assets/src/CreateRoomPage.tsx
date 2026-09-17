import { useState } from "react";

import {
  claimSampleSession,
  isSessionResponse,
  requestSampleAdmission,
  type RoomConnection,
} from "./sampleAdmission";

type RoomSnapshot = {
  room_id: string;
  incarnation_id: string;
  tenant_id: string;
  created_by_actor_id: string;
  lifecycle: string;
};

type RoomResponse = {
  room: RoomSnapshot;
};

export type { RoomConnection } from "./sampleAdmission";

type CreateRoomPageProps = {
  onCreated: (connection: RoomConnection) => void;
};

function createRoomId() {
  if (typeof globalThis.crypto?.randomUUID === "function") {
    return `room_${globalThis.crypto.randomUUID()}`;
  }

  if (typeof globalThis.crypto?.getRandomValues === "function") {
    const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

    return `room_${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  return `room_${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 14)}`;
}

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
  const [roomId] = useState(createRoomId);
  const [room, setRoom] = useState<RoomSnapshot>();
  const [error, setError] = useState<string>();
  const [creating, setCreating] = useState(false);

  async function createRoom() {
    setCreating(true);
    setError(undefined);

    try {
      const admission = await requestSampleAdmission("/sample/calls");

      if (admission) {
        onCreated(await claimSampleSession(admission));
        return;
      }

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

        if (isSessionResponse(payload)) {
          onCreated({
            incarnationId: createdRoom.incarnation_id,
            participant: payload.participant,
            session: payload.session,
          });
          return;
        }

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

      onCreated({
        incarnationId: createdRoom.incarnation_id,
        participant: sessionPayload.participant,
        session: sessionPayload.session,
      });
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
