import type { Participant } from "@vxpipe/core";

function EmptyValue({ children }: { children: string }) {
  return <p className="vx-participant-empty">{children}</p>;
}

export function ParticipantDetails({
  participant,
}: {
  participant: Participant | null;
}) {
  if (participant === null) {
    return (
      <section className="vx-participant-details" aria-label="Participant details">
        <EmptyValue>No participant configuration is available.</EmptyValue>
      </section>
    );
  }

  return (
    <section className="vx-participant-details" aria-label="Participant details">
      <header className="vx-participant-detail-header">
        <span className={`vx-avatar vx-${participant.role}`}>
          {participant.name.slice(0, 1)}
        </span>
        <div>
          <h2>{participant.name}</h2>
          {participant.description && <p>{participant.description}</p>}
        </div>
      </header>

      <section className="vx-participant-detail-section">
        <h3>Capabilities</h3>
        {participant.capabilities.length === 0 ? (
          <EmptyValue>No capabilities configured.</EmptyValue>
        ) : (
          <div className="vx-capability-grid">
            {participant.capabilities.map((capability) => (
              <article key={`${capability.name}-${capability.provider}`}>
                <strong>{capability.name}</strong>
                <span>{capability.provider}</span>
                {capability.model && <code>{capability.model}</code>}
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="vx-participant-detail-section">
        <h3>System prompt</h3>
        {participant.systemPrompt ? (
          <pre className="vx-system-prompt">{participant.systemPrompt}</pre>
        ) : (
          <EmptyValue>No system prompt configured.</EmptyValue>
        )}
      </section>

      <section className="vx-participant-detail-section">
        <h3>Transfer policies</h3>
        {participant.transferPolicies.length === 0 ? (
          <EmptyValue>No transfer policies configured.</EmptyValue>
        ) : (
          <ul className="vx-participant-detail-list">
            {participant.transferPolicies.map((policy) => (
              <li key={policy.name}>
                <strong>{policy.name}</strong>
                <span>{policy.description}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="vx-participant-detail-section">
        <h3>Tools available</h3>
        {participant.tools.length === 0 ? (
          <EmptyValue>No tools available.</EmptyValue>
        ) : (
          <ul className="vx-participant-detail-list vx-tool-list">
            {participant.tools.map((tool) => (
              <li key={tool.name}>
                <code>{tool.name}</code>
                <span>{tool.description}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </section>
  );
}
