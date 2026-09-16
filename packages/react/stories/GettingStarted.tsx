import { useState } from "react";

export type Example = "voice" | "agents" | "human";
const examples: {
  id: Example;
  title: string;
  description: string;
  participants: string[];
  detail: string;
}[] = [
  {
    id: "voice",
    title: "Voice conversation",
    description:
      "Meet your first voice agent. Type or talk, and follow its response as it happens.",
    participants: ["You", "Assistant"],
    detail: "Streaming text + audio",
  },
  {
    id: "agents",
    title: "Agent handoff",
    description:
      "Watch a concierge pass the conversation to a specialist, with context intact.",
    participants: ["You", "Concierge", "Specialist"],
    detail: "Multiple agents, one call",
  },
  {
    id: "human",
    title: "Human handoff",
    description:
      "Bring a support teammate into the call through a separate, explicit acceptance step.",
    participants: ["You", "Agent", "Support"],
    detail: "A second browser seat",
  },
];

/** Host application composition, deliberately outside @vxpipe/react's exports. */
export function GettingStarted({
  ready,
  onTry,
}: {
  ready: boolean;
  onTry: (example: Example) => void;
}) {
  const [configured, setConfigured] = useState(ready);
  const [showProviders, setShowProviders] = useState(false);
  const [installed, setInstalled] = useState(ready);
  const [saved, setSaved] = useState(false);
  const complete = configured && installed;
  return (
    <main className="prototype-home">
      <header className="prototype-home-heading">
        <div>
          <h1>Make your first call.</h1>
          <p>
            A small workspace to set things up, try a definition,
            <br className="prototype-desktop-break" /> and see what happens
            inside a conversation.
          </p>
        </div>
        <span
          className={`prototype-setup-status ${complete ? "is-ready" : ""}`}
        >
          {complete
            ? "Setup complete"
            : `${2 + Number(configured) + Number(installed)} of 4 steps complete`}
        </span>
      </header>
      <section className="prototype-setup" aria-label="Setup checklist">
        <div className="prototype-section-heading">
          <h2>Your workspace</h2>
          <span>Demo tenant</span>
        </div>
        <ol>
          <li>
            <span className="prototype-step done">1</span>
            <div>
              <h3>Platform access</h3>
              <p>Your platform API key gives you access to setup.</p>
            </div>
            <span className="prototype-complete">Configured</span>
          </li>
          <li>
            <span className="prototype-step done">2</span>
            <div>
              <h3>Demo tenant</h3>
              <p>A dedicated place for your example calls and credentials.</p>
            </div>
            <span className="prototype-complete">Created</span>
          </li>
          <li className={!configured ? "prototype-next-step" : ""}>
            <span className={`prototype-step ${configured ? "done" : ""}`}>
              3
            </span>
            <div>
              <h3>Speech + model services</h3>
              <p>
                {configured
                  ? "Deepgram for speech recognition and synthesis. Google for the model."
                  : "Connect speech recognition, speech synthesis and a language model."}
              </p>
            </div>
            {configured ? (
              <span className="prototype-complete">Configured</span>
            ) : (
              <button
                className="prototype-button primary"
                onClick={() => setShowProviders(!showProviders)}
              >
                {showProviders ? "Close setup" : "Configure services"}
              </button>
            )}
          </li>
          <li>
            <span className={`prototype-step ${installed ? "done" : ""}`}>
              4
            </span>
            <div>
              <h3>Example definitions</h3>
              <p>
                {installed
                  ? "Three examples published and ready to explore."
                  : "Install three small definitions in your demo tenant."}
              </p>
            </div>
            {installed ? (
              <span className="prototype-complete">Installed</span>
            ) : (
              <button
                className="prototype-button"
                disabled={!configured}
                onClick={() => setInstalled(true)}
              >
                Install examples
              </button>
            )}
          </li>
        </ol>
        {showProviders && (
          <form
            className="prototype-provider-form"
            onSubmit={(event) => {
              event.preventDefault();
              setConfigured(true);
              setShowProviders(false);
              setSaved(true);
            }}
          >
            <h3>Connect your services</h3>
            <p>
              Prototype form: use any sample values. Nothing is sent or saved.
            </p>
            <div>
              <label>
                Deepgram API key <span>One key for STT and TTS</span>
                <input
                  name="deepgram"
                  type="password"
                  required
                  autoComplete="off"
                  placeholder="Sample value"
                />
              </label>
              <label>
                Google API key <span>Language model</span>
                <input
                  name="google"
                  type="password"
                  required
                  autoComplete="off"
                  placeholder="Sample value"
                />
              </label>
            </div>
            <button className="prototype-button primary" type="submit">
              Save credentials
            </button>
          </form>
        )}
        {saved && (
          <p role="status" className="prototype-save-note">
            Sample setup updated for this preview.
          </p>
        )}
      </section>
      <section className="prototype-examples" aria-label="Example calls">
        <div className="prototype-section-heading">
          <div>
            <h2>Try a conversation</h2>
            <p>Start simple. Then bring more people into the call.</p>
          </div>
          <span>3 examples</span>
        </div>
        <div className="prototype-example-list">
          {examples.map((example, index) => (
            <article className="prototype-example" key={example.id}>
              <div
                className="prototype-flow"
                aria-label={example.participants.join(" to ")}
              >
                {example.participants.map((name, i) => (
                  <div key={name}>
                    <span
                      className={`prototype-flow-node role-${i === 0 ? "caller" : name === "Support" ? "human" : "agent"}`}
                    >
                      {name.slice(0, 1)}
                    </span>
                    <span>{name}</span>
                  </div>
                ))}
              </div>
              <div className="prototype-example-copy">
                <div className="prototype-example-title">
                  <h3>{example.title}</h3>
                  {index === 0 && <span>Start here</span>}
                </div>
                <p>{example.description}</p>
                <span className="prototype-example-detail">
                  {example.detail}
                </span>
              </div>
              <div className="prototype-example-action">
                <span>
                  {complete
                    ? "Ready to try"
                    : configured
                      ? "Install examples first"
                      : "Needs speech + model services"}
                </span>
                <button
                  className="prototype-button"
                  disabled={!complete}
                  aria-label={`Try ${example.title.toLowerCase()}`}
                  onClick={() => onTry(example.id)}
                >
                  Try example
                  <svg
                    width="16"
                    height="16"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    aria-hidden="true"
                  >
                    <path d="M4 12h16m-6-6 6 6-6 6" />
                  </svg>
                </button>
              </div>
            </article>
          ))}
        </div>
      </section>
      <footer className="prototype-home-footer">
        Examples use the same call engine and debug console as your own
        definitions.
      </footer>
    </main>
  );
}
