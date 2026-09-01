export type BackendState = "connected" | "disconnected" | "loading";

export interface BackendStatusProps {
  state: BackendState;
}

const copy: Record<BackendState, { detail: string; title: string }> = {
  connected: {
    detail: "Fastify is ready to orchestrate sample sessions.",
    title: "Sample backend connected",
  },
  disconnected: {
    detail: "Start the TypeScript backend, then refresh this page.",
    title: "Sample backend unavailable",
  },
  loading: {
    detail: "Checking the local development services.",
    title: "Connecting to sample backend",
  },
};

export function BackendStatus({ state }: BackendStatusProps) {
  const content = copy[state];

  return (
    <section className={`backend-status backend-status--${state}`} aria-live="polite">
      <span className="backend-status__signal" aria-hidden="true" />
      <div>
        <p className="eyebrow">Development services</p>
        <h2>{content.title}</h2>
        <p>{content.detail}</p>
      </div>
    </section>
  );
}
