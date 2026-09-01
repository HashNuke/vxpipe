export interface SampleSummary {
  description: string;
  id: string;
  status: "available" | "planned";
  title: string;
}

export interface SampleCardProps {
  sample: SampleSummary;
}

export function SampleCard({ sample }: SampleCardProps) {
  const available = sample.status === "available";

  return (
    <article className="sample-card">
      <div className="sample-card__header">
        <span className={`sample-card__status sample-card__status--${sample.status}`}>
          {available ? "Available" : "Planned"}
        </span>
        <span className="sample-card__number" aria-hidden="true">
          01
        </span>
      </div>
      <h3>{sample.title}</h3>
      <p>{sample.description}</p>
      <button type="button" disabled={!available}>
        {available ? "Open sample" : "Coming with the V1 media protocol"}
      </button>
    </article>
  );
}
