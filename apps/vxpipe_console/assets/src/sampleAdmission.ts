export type ParticipantSnapshot = {
  incarnation_id: string;
  participant_id: string;
  role: string;
  room_id: string;
  state: string;
};

export type GatewaySession = {
  session_id: string;
  expires_at: string;
  transport: {
    type: "smallwebrtc";
    endpoint: string;
    request_data: { session_id: string };
  };
};

export type ManagedAdmission = {
  tenant_key: string;
  call_id: string;
  participant_key: string;
  join_token: {
    token: string;
    expires_at: string;
  };
};

export type RoomConnection = {
  incarnationId: string;
  participant: ParticipantSnapshot;
  session: GatewaySession;
};

type SessionResponse = {
  participant: ParticipantSnapshot;
  session: GatewaySession;
};

type ManagedSessionResponse = SessionResponse & {
  call: {
    call_id: string;
    started_at: string;
    state: "running";
  };
};

export async function requestSampleAdmission(
  endpoint: string,
): Promise<ManagedAdmission | undefined> {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });

  if (response.status === 404) {
    return undefined;
  }

  if (!response.ok) {
    throw new Error("The sample backend could not issue an admission.");
  }

  const payload: unknown = await response.json();

  if (!isManagedAdmission(payload)) {
    throw new Error("The sample backend returned an invalid admission response.");
  }

  return payload;
}

export async function claimSampleSession(admission: ManagedAdmission): Promise<RoomConnection> {
  const response = await fetch(sessionPath(admission), {
    method: "POST",
    headers: {
      authorization: `Bearer ${admission.join_token.token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    throw new Error("The gateway could not start the participant session.");
  }

  const payload: unknown = await response.json();

  if (!isManagedSessionResponse(payload)) {
    throw new Error("The gateway returned an invalid participant session.");
  }

  return {
    incarnationId: payload.participant.incarnation_id,
    participant: payload.participant,
    session: payload.session,
  };
}

export function isSessionResponse(value: unknown): value is SessionResponse {
  if (
    !value ||
    typeof value !== "object" ||
    !("participant" in value) ||
    !("session" in value)
  ) {
    return false;
  }

  const { participant, session } = value;

  return (
    !!participant &&
    typeof participant === "object" &&
    "participant_id" in participant &&
    typeof participant.participant_id === "string" &&
    "incarnation_id" in participant &&
    typeof participant.incarnation_id === "string" &&
    !!session &&
    typeof session === "object" &&
    "session_id" in session &&
    typeof session.session_id === "string" &&
    "transport" in session &&
    !!session.transport &&
    typeof session.transport === "object" &&
    "type" in session.transport &&
    session.transport.type === "smallwebrtc" &&
    "endpoint" in session.transport &&
    typeof session.transport.endpoint === "string" &&
    "request_data" in session.transport &&
    !!session.transport.request_data &&
    typeof session.transport.request_data === "object" &&
    "session_id" in session.transport.request_data &&
    session.transport.request_data.session_id === session.session_id
  );
}

function isManagedAdmission(value: unknown): value is ManagedAdmission {
  if (
    !value ||
    typeof value !== "object" ||
    !("tenant_key" in value) ||
    typeof value.tenant_key !== "string" ||
    !("call_id" in value) ||
    typeof value.call_id !== "string" ||
    !("participant_key" in value) ||
    typeof value.participant_key !== "string" ||
    !("join_token" in value) ||
    !value.join_token ||
    typeof value.join_token !== "object"
  ) {
    return false;
  }

  return (
    "token" in value.join_token &&
    typeof value.join_token.token === "string" &&
    "expires_at" in value.join_token &&
    typeof value.join_token.expires_at === "string"
  );
}

function isManagedSessionResponse(value: unknown): value is ManagedSessionResponse {
  return (
    isSessionResponse(value) &&
    "call" in value &&
    !!value.call &&
    typeof value.call === "object" &&
    "call_id" in value.call &&
    typeof value.call.call_id === "string" &&
    "state" in value.call &&
    value.call.state === "running"
  );
}

function sessionPath(admission: ManagedAdmission): string {
  return `/api/tenants/${encodeURIComponent(admission.tenant_key)}/calls/${encodeURIComponent(admission.call_id)}/participants/${encodeURIComponent(admission.participant_key)}/sessions`;
}
