import { BackendStatus, type BackendState } from "../components/backend-status";
import { SampleCard, type SampleSummary } from "../components/sample-card";

export interface SamplesPageProps {
  backendState: BackendState;
  samples: SampleSummary[];
}

export function SamplesPage({ backendState, samples }: SamplesPageProps) {
  return (
    <main>
      <header className="hero">
        <div className="hero__mark" aria-hidden="true">
          VX
        </div>
        <div className="hero__copy">
          <p className="eyebrow">Vxpipe field kit</p>
          <h1>Build voice rooms from the outside in.</h1>
          <p className="hero__lede">
            Dogfood the public API, media sockets, and failure states in small,
            inspectable applications—the same examples end users can build upon.
          </p>
        </div>
      </header>

      <BackendStatus state={backendState} />

      <section className="samples" aria-labelledby="samples-heading">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Samples</p>
            <h2 id="samples-heading">Voice platform exercises</h2>
          </div>
          <p>{samples.length} registered</p>
        </div>

        {backendState === "loading" ? (
          <div className="sample-placeholder" aria-label="Loading samples" />
        ) : samples.length > 0 ? (
          <div className="sample-grid">
            {samples.map((sample) => (
              <SampleCard key={sample.id} sample={sample} />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <h3>No samples available</h3>
            <p>The backend is connected, but it did not publish any examples.</p>
          </div>
        )}
      </section>
    </main>
  );
}
