import { useEffect, useMemo, useState } from "react";
import { CallConsole } from "../src/index.js";
import {
  createFixtureClient,
  type ExampleScenario,
  type Scenario,
} from "./fixtureClient.js";
import { GettingStarted, type Example } from "./GettingStarted.js";

export interface WorkbenchProps {
  scenario?: Scenario;
  theme?: "light" | "dark";
  page?: "console" | "setup";
  ready?: boolean;
  initialTab?: "chat" | "variables" | "metrics" | "participants";
  animateSpeech?: boolean;
}

export function Workbench({
  scenario = "conversation",
  theme: initialTheme = "dark",
  page: initialPage = "console",
  ready = true,
  initialTab = "chat",
  animateSpeech = false,
}: WorkbenchProps) {
  const [page, setPage] = useState(initialPage);
  const [theme, setTheme] = useState(initialTheme);
  const [run, setRun] = useState(0);
  const [selectedScenario, setScenario] = useState(scenario);
  const [startScenario, setStartScenario] =
    useState<ExampleScenario>("conversation");
  const client = useMemo(
    () => createFixtureClient(selectedScenario, startScenario),
    [selectedScenario, startScenario, run],
  );
  useEffect(() => {
    if (!animateSpeech || page !== "console") return;
    const timer = window.setInterval(() => client.advanceSpeech(), 650);
    return () => window.clearInterval(timer);
  }, [animateSpeech, client, page]);
  const openExample = (example: Example) => {
    setStartScenario(
      example === "agents"
        ? "handoff"
        : example === "human"
          ? "human-handoff"
          : "conversation",
    );
    setScenario("ready");
    setRun((n) => n + 1);
    setPage("console");
  };
  return (
    <div className="prototype-app" data-vx-theme={theme}>
      <header className="prototype-topbar">
        <a
          className="prototype-brand"
          href="#"
          onClick={(event) => {
            event.preventDefault();
            setPage("setup");
          }}
        >
          <svg
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            aria-hidden="true"
          >
            <path
              d="M3 5h5l4 14 4-14h5M3 12h5m8 0h5"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinejoin="round"
            />
          </svg>
          vxpipe
        </a>
        <nav aria-label="Workspace">
          <button
            aria-current={page === "setup" ? "page" : undefined}
            onClick={() => setPage("setup")}
          >
            Getting started
          </button>
          <button
            aria-current={page === "console" ? "page" : undefined}
            onClick={() => setPage("console")}
          >
            Console
          </button>
        </nav>
        <div className="prototype-workspace">
          <button
            aria-label={
              theme === "light"
                ? "Switch to dark theme"
                : "Switch to light theme"
            }
            onClick={() => setTheme(theme === "light" ? "dark" : "light")}
          >
            {theme === "light" ? "Dark" : "Light"}
          </button>
        </div>
      </header>
      {page === "console" ? (
        <div className="prototype-console-page">
          <CallConsole
            key={`${run}-${selectedScenario}`}
            client={client}
            initialTab={initialTab}
            maxHeight="calc(100dvh - 132px)"
            theme={theme}
          />
        </div>
      ) : (
        <GettingStarted key={String(ready)} ready={ready} onTry={openExample} />
      )}
    </div>
  );
}
