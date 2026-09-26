import type { CSSProperties } from 'react';
import '../styles/call-room.css';

export interface AgentProfile {
  id: 'a' | 'b' | 'c';
  name: string;
  kind: 'agent' | 'human';
  capabilities: string[];
  /** Plain-language caption shown while this profile is at the front. */
  storyline: string;
}

export interface RoomVisualProps {
  /** Call-wide services shown in the "shared by everyone" strip. */
  services?: string[];
  /** Capability chips on the caller participant. */
  callerCapabilities?: string[];
  /** Agent profiles sharing the turntable's single active contact. */
  profiles?: AgentProfile[];
}

const DEFAULT_SERVICES = [
  'call variables',
  'transcripts',
  'call recording',
  'policies',
];

const DEFAULT_CALLER_CAPABILITIES = ['speech-to-text'];

const DEFAULT_PROFILES: AgentProfile[] = [
  {
    id: 'a',
    name: 'concierge',
    kind: 'agent',
    capabilities: ['LLM', 'text-to-speech', 'guardrails'],
    storyline: 'The concierge agent greets the caller and fills in call variables.',
  },
  {
    id: 'b',
    name: 'billing',
    kind: 'agent',
    capabilities: ['LLM', 'text-to-speech'],
    storyline: 'Billing takes over. The call variables carry across the transfer.',
  },
  {
    id: 'c',
    name: 'human specialist',
    kind: 'human',
    capabilities: ['private briefing'],
    storyline: 'A human specialist joins after a private briefing.',
  },
];

/** Staggered clocks so activation runs top → middle → bottom. */
const PROFILE_DELAYS: Record<AgentProfile['id'], string> = {
  a: '0s',
  b: '-8s',
  c: '-4s',
};

function PersonIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <circle cx="12" cy="8" r="3.6" />
      <path d="M4.8 19.4c1.4-3.4 4.1-5 7.2-5s5.8 1.6 7.2 5" />
    </svg>
  );
}

function BotIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="6" y="7" width="12" height="10" rx="3" />
      <circle cx="10" cy="12" r="0.6" fill="currentColor" />
      <circle cx="14" cy="12" r="0.6" fill="currentColor" />
      <path d="M12 7V4.5" />
      <circle cx="12" cy="3.6" r="0.7" fill="currentColor" />
    </svg>
  );
}

function CallIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.79 19.79 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" />
      <path d="M2.5 9a6 6 0 0 0 0 6" />
    </svg>
  );
}

export default function CallRoomVisual({
  services = DEFAULT_SERVICES,
  callerCapabilities = DEFAULT_CALLER_CAPABILITIES,
  profiles = DEFAULT_PROFILES,
}: RoomVisualProps) {
  return (
    <figure
      className="crv"
      role="img"
      aria-label="Diagram of a VxPipe call: call variables, transcripts, recording, and policies are shared by everyone on the call. A caller phones in. A concierge agent answers, transfers the caller to a billing agent with the call variables intact, and then a human specialist joins after a private briefing."
    >
      <div className="crv-room">
        <header className="crv-room-head">
          <span className="crv-room-title">call room</span>
          <span className="crv-live">
            <span className="crv-live-dot" aria-hidden="true" />
            live
          </span>
        </header>

        <section className="crv-managed" aria-label="shared by everyone on the call">
          <span className="crv-managed-label">shared by everyone on the call</span>
          <ul className="crv-managed-list">
            {services.map((service) => (
              <li key={service}>{service}</li>
            ))}
          </ul>
        </section>

        <div className="crv-grid">
          <section className="crv-participant crv-participant--caller" aria-label="caller participant">
            <header className="crv-p-head">
              <span className="crv-avatar crv-avatar--caller" aria-hidden="true">
                <PersonIcon />
                <span className="crv-ring" />
                <span className="crv-ring crv-ring--late" />
              </span>
              <span className="crv-p-name">caller</span>
            </header>
            <ul className="crv-caps">
              {callerCapabilities.map((capability) => (
                <li key={capability} className="crv-cap crv-cap--caller">
                  {capability}
                </li>
              ))}
              <li className="crv-cap crv-cap--caller crv-cap--tel">
                <CallIcon />
                <span className="crv-tel-number">+1 (415) 555-0132</span>
              </li>
            </ul>
          </section>

          <div className="crv-lane" aria-hidden="true">
            <span className="crv-lane-track" />
            <span className="crv-lane-dot crv-lane-dot--out" />
            <span className="crv-lane-dot crv-lane-dot--back" />
            <span className="crv-mixer">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
              >
                <path d="M5 6v13M12 3v18M19 8v9" />
                <circle cx="5" cy="12" r="1.8" fill="currentColor" stroke="none" />
                <circle cx="12" cy="9" r="1.8" fill="currentColor" stroke="none" />
                <circle cx="19" cy="13" r="1.8" fill="currentColor" stroke="none" />
              </svg>
              room mixer
            </span>
          </div>

          <section className="crv-agents" aria-label="agent profiles">
            <div className="crv-deck">
              <ul className="crv-profiles">
                {profiles.map((profile) => (
                  <li
                    key={profile.id}
                    className={`crv-profile crv-profile--${profile.id}`}
                    style={{ animationDelay: PROFILE_DELAYS[profile.id] } as CSSProperties}
                  >
                    <span className="crv-card-head">
                      <span className="crv-card-icon">
                        {profile.kind === 'human' ? <PersonIcon /> : <BotIcon />}
                      </span>
                      <span className="crv-profile-name">{profile.name}</span>
                      <span className="crv-profile-kind">
                        {profile.kind === 'human' ? 'transfer target' : 'agent'}
                      </span>
                    </span>
                    <ul className="crv-caps">
                      {profile.capabilities.map((capability) => (
                        <li key={capability} className="crv-cap crv-cap--mini">
                          {capability}
                        </li>
                      ))}
                    </ul>
                  </li>
                ))}
              </ul>
            </div>
          </section>
        </div>

        <ol className="crv-story" aria-hidden="true">
          {profiles.map((profile) => (
            <li
              key={profile.id}
              className="crv-story-line"
              style={{ animationDelay: PROFILE_DELAYS[profile.id] } as CSSProperties}
            >
              {profile.storyline}
            </li>
          ))}
        </ol>
      </div>
    </figure>
  );
}
