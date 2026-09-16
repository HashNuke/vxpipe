import type { Participant } from "@vxpipe/core";

export function Participants({
  participants,
}: {
  participants: readonly Participant[];
}) {
  return (
    <aside className="vx-participants" aria-label="Participants">
      <div className="vx-section-title">
        <h2>Participants</h2>
        <span>{participants.length}</span>
      </div>
      <ul>
        {participants.map((person) => (
          <li
            key={person.id}
            className={person.state === "left" ? "vx-left" : ""}
          >
            <span className={`vx-avatar vx-${person.role}`}>
              {person.name.slice(0, 1)}
            </span>
            <div>
              <strong>{person.name}</strong>
              <p>{person.description}</p>
              <span className={`vx-presence vx-${person.state}`}>
                <i />
                {person.state}
              </span>
            </div>
          </li>
        ))}
      </ul>
    </aside>
  );
}
