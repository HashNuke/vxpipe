import type { Participant } from "@vxpipe/core";

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
        {participants.map((person) => (
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
              <span className={`vx-avatar vx-${person.role}`}>
                {person.name.slice(0, 1)}
              </span>
              <span className="vx-participant-summary">
                <strong>{person.name}</strong>
                <span className={`vx-presence vx-${person.state}`}>
                  <i />
                  {person.role === "caller" && person.connection
                    ? `${person.connection.label} · ${person.state}`
                    : person.state}
                </span>
              </span>
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
