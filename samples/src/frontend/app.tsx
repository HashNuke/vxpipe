import { useEffect, useState } from "react";

import type { BackendState } from "./components/backend-status";
import type { SampleSummary } from "./components/sample-card";
import { SamplesPage } from "./pages/samples-page";

interface SamplesResponse {
  samples: SampleSummary[];
}

function isSampleSummary(value: unknown): value is SampleSummary {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const sample = value as Record<string, unknown>;

  return (
    typeof sample.description === "string" &&
    typeof sample.id === "string" &&
    (sample.status === "available" || sample.status === "planned") &&
    typeof sample.title === "string"
  );
}

function isSamplesResponse(value: unknown): value is SamplesResponse {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const response = value as Record<string, unknown>;
  return Array.isArray(response.samples) && response.samples.every(isSampleSummary);
}

export function App() {
  const [backendState, setBackendState] = useState<BackendState>("loading");
  const [samples, setSamples] = useState<SampleSummary[]>([]);

  useEffect(() => {
    const abortController = new AbortController();

    async function loadSamples() {
      try {
        const [healthResponse, samplesResponse] = await Promise.all([
          fetch("/api/health", { signal: abortController.signal }),
          fetch("/api/samples", { signal: abortController.signal }),
        ]);

        if (!healthResponse.ok || !samplesResponse.ok) {
          throw new Error("Sample backend request failed");
        }

        const payload: unknown = await samplesResponse.json();

        if (!isSamplesResponse(payload)) {
          throw new Error("Sample backend returned an invalid catalog");
        }

        setSamples(payload.samples);
        setBackendState("connected");
      } catch {
        if (!abortController.signal.aborted) {
          setBackendState("disconnected");
        }
      }
    }

    void loadSamples();

    return () => abortController.abort();
  }, []);

  return <SamplesPage backendState={backendState} samples={samples} />;
}
