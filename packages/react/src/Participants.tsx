import type { Participant, ParticipantConnection } from "@vxpipe/core";

function presenceLabel(state: Participant["state"]) {
  return state === "listening" || state === "speaking" ? "connected" : state;
}

function connectionLabel(connection: ParticipantConnection) {
  return connection.kind === "webrtc" ? "WebRTC" : connection.phoneNumber;
}

export function Participants({
  participants,
  selectedParticipantId,
  onSelect,
}: {
  participants: readonly Participant[];
  selectedParticipantId: string | null;
  onSelect: (participantId: string) => void;
}) {
  return (
    <aside className="vx-participants" aria-label="Participants">
      <div className="vx-section-title">
        <h2>Participants</h2>
        <span>{participants.length}</span>
      </div>
      <ul>
        {participants.map((person) => {
          const presence = presenceLabel(person.state);
          const callerConnection =
            person.role === "caller" ? person.connection : undefined;
          const callerConnectionLabel = callerConnection
            ? connectionLabel(callerConnection)
            : undefined;
          return (
            <li key={person.id}>
              <button
                aria-label={`View ${person.name} details`}
                aria-pressed={selectedParticipantId === person.id}
                className={`vx-participant-button ${
                  person.state === "inactive" || person.state === "left"
                    ? "vx-participant-muted"
                    : ""
                } ${selectedParticipantId === person.id ? "vx-participant-selected" : ""}`}
                onClick={() => onSelect(person.id)}
              >
                <span className="vx-avatar-shell">
                  <span className={`vx-avatar vx-${person.role}`}>
                    {person.name.slice(0, 1)}
                  </span>
                  {person.state === "speaking" && (
                    <span
                      className="vx-avatar-audiogram"
                      role="img"
                      aria-label={`${person.name} is speaking`}
                    >
                      {[0, 1, 2, 3, 4].map((bar) => (
                        <i key={bar} />
                      ))}
                    </span>
                  )}
                </span>
                <span className="vx-participant-summary">
                  <strong>{person.name}</strong>
                  <span
                    className={`vx-presence vx-${presence}`}
                    aria-label={
                      callerConnectionLabel
                        ? `${callerConnectionLabel}, ${presence}`
                        : undefined
                    }
                    title={
                      callerConnectionLabel
                        ? `${callerConnectionLabel} · ${presence}`
                        : undefined
                    }
                  >
                    <i />
                    {callerConnectionLabel ?? presence}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </aside>
  );
}
