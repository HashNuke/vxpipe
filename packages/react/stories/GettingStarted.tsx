import { useState } from "react";

export type Example = "voice" | "agents" | "human";
type Service = "stt" | "tts" | "llm" | "telephony";

const services: Array<{ id: Service; label: string; provider: string; detail: string }> = [
  { id: "stt", label: "STT", provider: "Speech recognition", detail: "Turn audio into text." },
  { id: "tts", label: "TTS", provider: "Speech synthesis", detail: "Give the agent a voice." },
  { id: "llm", label: "LLM", provider: "Language model", detail: "Reason over each turn." },
  { id: "telephony", label: "Telephony", provider: "Phone calls", detail: "Connect a carrier when you are ready." },
];

const examples: { id: Example; title: string; description: string; participants: string[]; detail: string }[] = [
  { id: "voice", title: "Voice conversation", description: "Meet your first voice agent. Type or talk, and follow its response as it happens.", participants: ["You", "Assistant"], detail: "Streaming text + audio" },
  { id: "agents", title: "Agent handoff", description: "Watch a concierge pass the conversation to a specialist, with context intact.", participants: ["You", "Concierge", "Specialist"], detail: "Multiple agents, one call" },
  { id: "human", title: "Human handoff", description: "Bring a support teammate into the call through a separate, explicit acceptance step.", participants: ["You", "Agent", "Support"], detail: "A second browser seat" },
];

/** Host application composition, deliberately outside @vxpipe/react's exports. */
export function GettingStarted({ ready, onTry }: { ready: boolean; onTry: (example: Example) => void }) {
  const [tenantName, setTenantName] = useState("DemoTenant");
  const [tenantDraft, setTenantDraft] = useState("DemoTenant");
  const [renaming, setRenaming] = useState(false);
  const [showServices, setShowServices] = useState(false);
  const [selectedServices, setSelectedServices] = useState<Service[]>(["stt", "tts", "llm"]);
  const [credentials, setCredentials] = useState<Record<Service, string>>({ stt: "", tts: "", llm: "", telephony: "" });
  const [validated, setValidated] = useState<Service[]>(ready ? ["stt", "tts", "llm"] : []);
  const [validatedAt, setValidatedAt] = useState(ready);
  const [installed, setInstalled] = useState(ready);
  const configured = selectedServices.length > 0 && validated.length === selectedServices.length;
  const complete = configured && installed;
  const stepsComplete = 2 + Number(configured) + Number(installed);

  function toggleService(service: Service) {
    setSelectedServices((current) => current.includes(service) ? current.filter((item) => item !== service) : [...current, service]);
    setValidated([]);
    setValidatedAt(false);
  }

  function validateCredentials(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const nextValidated = selectedServices.filter((service) => credentials[service].trim());
    setValidated(nextValidated);
    setValidatedAt(nextValidated.length === selectedServices.length);
  }

  return (
    <main className="prototype-home">
      <header className="prototype-home-heading">
        <div>
          <span className="prototype-eyebrow">FIRST-RUN SETUP</span>
          <h1>Make your first call.</h1>
          <p>Set up one tenant, verify the services it will use, and load a small definition you can run immediately.</p>
        </div>
        <span className={`prototype-setup-status ${complete ? "is-ready" : ""}`}>{complete ? "Setup complete" : `${stepsComplete} of 4 steps complete`}</span>
      </header>
      <section className="prototype-setup" aria-label="Setup checklist">
        <div className="prototype-section-heading">
          <div><h2>Your workspace</h2><p>Setup resumes here if you leave before it is finished.</p></div>
          <span>Tenant setup</span>
        </div>
        <ol>
          <li><span className="prototype-step done">1</span><div><h3>Platform access</h3><p>Your platform session gives you access to setup.</p></div><span className="prototype-complete">Connected</span></li>
          <li className="prototype-tenant-row">
            <span className="prototype-step done">2</span><div><h3>{tenantName}</h3><p>Created automatically for your first call. You can rename it any time.</p></div>
            {renaming ? <form className="prototype-inline-form" onSubmit={(event) => { event.preventDefault(); if (tenantDraft.trim()) setTenantName(tenantDraft.trim()); setRenaming(false); }}><label><span className="prototype-sr-only">Tenant name</span><input aria-label="Tenant name" value={tenantDraft} onChange={(event) => setTenantDraft(event.target.value)} /></label><button className="prototype-button primary" type="submit">Save tenant name</button></form> : <button className="prototype-button" onClick={() => { setTenantDraft(tenantName); setRenaming(true); }}>Rename tenant</button>}
          </li>
          <li className={!configured ? "prototype-next-step" : ""}>
            <span className={`prototype-step ${configured ? "done" : ""}`}>3</span><div><h3>Service credentials</h3><p>{configured ? `${selectedServices.length} service${selectedServices.length === 1 ? "" : "s"} validated for ${tenantName}.` : "Choose the services this tenant will use, then verify each credential with its provider."}</p>{validatedAt && configured ? <span className="prototype-validation-time">Last validated just now · API checks passed</span> : null}</div>
            {configured ? <span className="prototype-complete">Validated</span> : <button className="prototype-button primary" onClick={() => setShowServices(!showServices)}>{showServices ? "Close setup" : "Choose services"}</button>}
          </li>
          <li><span className={`prototype-step ${installed ? "done" : ""}`}>4</span><div><h3>Sample call definitions</h3><p>{installed ? "Starter definitions are loaded in this tenant." : "Load the checked-in starter definition into your demo tenant after validation."}</p></div>{installed ? <span className="prototype-complete">Loaded</span> : <button className="prototype-button" disabled={!configured} onClick={() => setInstalled(true)}>Load sample definitions</button>}</li>
        </ol>
        {showServices ? <form className="prototype-provider-form" onSubmit={validateCredentials}>
          <div className="prototype-provider-heading"><div><span className="prototype-eyebrow">SERVICE INVENTORY</span><h3>What should {tenantName} connect to?</h3><p>We will make a provider API call for every selected service before saving its validated state.</p></div><span className="prototype-provider-count">{selectedServices.length} selected</span></div>
          <div className="prototype-service-options" role="group" aria-label="Services">{services.map((service) => <label className={`prototype-service-option ${selectedServices.includes(service.id) ? "is-selected" : ""}`} key={service.id}><input type="checkbox" aria-label={service.label === "Telephony" ? "Telephony" : service.label} checked={selectedServices.includes(service.id)} onChange={() => toggleService(service.id)} /><span className="prototype-service-mark">{service.label.slice(0, 1)}</span><span><strong>{service.label}</strong><small>{service.provider}</small></span></label>)}</div>
          {selectedServices.length ? <div className="prototype-credential-grid">{selectedServices.map((serviceId) => { const service = services.find((candidate) => candidate.id === serviceId); if (!service) return null; return <label key={service.id}>{service.label} API key<span>{service.detail}</span><input aria-label={`${service.label} API key`} type="password" autoComplete="off" value={credentials[service.id]} onChange={(event) => setCredentials({ ...credentials, [service.id]: event.target.value })} placeholder="Paste a key to validate" required /></label>; })}</div> : <p className="prototype-provider-empty">Select at least one service to continue.</p>}
          <div className="prototype-provider-actions"><span>Secrets are never shown again after saving.</span><button className="prototype-button primary" disabled={!selectedServices.length} type="submit">Validate credentials</button></div>
        </form> : null}
        {configured ? <p className="prototype-save-note" role="status">All selected services validated · Last validated just now</p> : null}
      </section>
      <section className="prototype-examples" aria-label="Example calls"><div className="prototype-section-heading"><div><h2>Try a conversation</h2><p>Starter experiences use the same call engine as your own definitions.</p></div><span>3 experiences</span></div><div className="prototype-example-list">{examples.map((example, index) => <article className="prototype-example" key={example.id}><div className="prototype-flow" aria-label={example.participants.join(" to ")}>{example.participants.map((name, i) => <div key={name}><span className={`prototype-flow-node role-${i === 0 ? "caller" : name === "Support" ? "human" : "agent"}`}>{name.slice(0, 1)}</span><span>{name}</span></div>)}</div><div className="prototype-example-copy"><div className="prototype-example-title"><h3>{example.title}</h3>{index === 0 && <span>Start here</span>}</div><p>{example.description}</p><span className="prototype-example-detail">{example.detail}</span></div><div className="prototype-example-action"><span>{complete ? "Ready to try" : configured ? "Load definitions first" : "Needs validated services"}</span><button className="prototype-button" disabled={!complete} aria-label={`Try ${example.title.toLowerCase()}`} onClick={() => onTry(example.id)}>Try example<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M4 12h16m-6-6 6 6-6 6" /></svg></button></div></article>)}</div></section>
      <footer className="prototype-home-footer">One starter call definition is included with this workspace. Add more from the Definitions area.</footer>
    </main>
  );
}
