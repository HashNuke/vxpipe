import type { GatewaySession } from "./sampleAdmission";

const DEFAULT_OFFER_URL = "/api/rtvi/offer";

const progressPhases = ["preparing", "cue", "releasing", "recovering"] as const;
const blockerKinds = ["speech_to_text", "text_to_speech", "model_inference", "tools",
  "media", "recording", "room_services", "other"] as const;

export type TransferProgress = {
  type: "progress";
  attemptId: string;
  phase: typeof progressPhases[number];
  blockers: Array<typeof blockerKinds[number]>;
  elapsedMs: number;
};

export type TransferControl =
  | { type: "preparation"; attemptId: string; participantId: string }
  | { type: "acceptance_ready"; attemptId: string }
  | { type: "active"; attemptId: string }
  | TransferProgress
  | { type: "error"; message: string };

export type TransferConnection = {
  accept: (attemptId: string) => void;
  close: () => void;
};

export type TransferConnectionCallbacks = {
  onControl: (control: TransferControl) => void;
  onClosed: () => void;
};

export async function openTransferConnection(
  session: GatewaySession,
  callbacks: TransferConnectionCallbacks,
): Promise<TransferConnection> {
  const peer = new RTCPeerConnection();
  const channel = peer.createDataChannel("vxpipe", { ordered: true });
  const microphone = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
  const offerUrl = session.transport.endpoint || DEFAULT_OFFER_URL;
  let remoteAudio: HTMLAudioElement | undefined;
  let connectionId: string | undefined;
  let closed = false;
  let closeNotified = false;
  const pendingCandidates: RTCIceCandidate[] = [];

  function close(notify: boolean) {
    if (closed) {
      return;
    }

    closed = true;
    microphone.getTracks().forEach((track) => track.stop());
    channel.close();
    peer.close();

    if (remoteAudio) {
      remoteAudio.pause();
      remoteAudio.srcObject = null;
    }

    if (notify && !closeNotified) {
      closeNotified = true;
      callbacks.onClosed();
    }
  }

  async function sendCandidate(candidate: RTCIceCandidate, id: string) {
    const response = await fetch(offerUrl, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        pc_id: id,
        candidates: [
          {
            candidate: candidate.candidate,
            sdp_mid: candidate.sdpMid,
            sdp_mline_index: candidate.sdpMLineIndex,
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error("The gateway rejected an ICE candidate.");
    }
  }

  peer.onicecandidate = (event) => {
    if (!event.candidate) {
      return;
    }

    if (connectionId) {
      void sendCandidate(event.candidate, connectionId).catch(() => close(true));
    } else {
      pendingCandidates.push(event.candidate);
    }
  };

  peer.onconnectionstatechange = () => {
    if (peer.connectionState === "closed" || peer.connectionState === "failed") {
      close(true);
    }
  };

  channel.onclose = () => close(true);
  channel.onmessage = (event) => {
    const control = decodeControl(event.data);

    if (control) {
      callbacks.onControl(control);
    }
  };

  peer.ontrack = (event) => {
    const stream = event.streams[0] ?? new MediaStream([event.track]);
    remoteAudio ??= new Audio();
    remoteAudio.autoplay = true;
    remoteAudio.srcObject = stream;

    void remoteAudio.play().catch(() => {
      callbacks.onControl({
        type: "error",
        message: "Browser audio playback was blocked. Allow audio and reconnect.",
      });
    });
  };

  microphone.getTracks().forEach((track) => peer.addTrack(track, microphone));

  try {
    const offer = await peer.createOffer();
    await peer.setLocalDescription(offer);

    const response = await fetch(offerUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        sdp: peer.localDescription?.sdp,
        type: peer.localDescription?.type,
        pc_id: null,
        restart_pc: false,
        requestData: session.transport.request_data,
      }),
    });

    if (!response.ok) {
      throw new Error("The gateway could not negotiate the destination media.");
    }

    const payload: unknown = await response.json();

    if (!isAnswer(payload)) {
      throw new Error("The gateway returned an invalid destination answer.");
    }

    const establishedConnectionId = payload.pc_id;
    connectionId = establishedConnectionId;
    await peer.setRemoteDescription({ type: "answer", sdp: payload.sdp });
    await Promise.all(
      pendingCandidates.map((candidate) => sendCandidate(candidate, establishedConnectionId)),
    );

    return {
      accept(attemptId) {
        if (!identifier(attemptId) || channel.readyState !== "open") {
          throw new Error("The transfer control channel is not ready.");
        }

        channel.send(
          JSON.stringify({
            id: acceptanceId(),
            type: "transfer.accept",
            data: { attempt_id: attemptId },
          }),
        );
      },
      close: () => close(false),
    };
  } catch (reason) {
    close(false);
    throw reason;
  }
}

function decodeControl(value: unknown): TransferControl | undefined {
  if (typeof value !== "string" || value.length > 4_096) {
    return undefined;
  }

  try {
    const message: unknown = JSON.parse(value);

    if (!message || typeof message !== "object" || !("type" in message) || !("data" in message)) {
      return undefined;
    }

    const data = message.data;

    if (!data || typeof data !== "object") {
      return undefined;
    }

    if (
      message.type === "transfer.preparation" &&
      "attempt_id" in data &&
      identifier(data.attempt_id) &&
      "participant_id" in data &&
      identifier(data.participant_id)
    ) {
      return {
        type: "preparation",
        attemptId: data.attempt_id,
        participantId: data.participant_id,
      };
    }

    if (message.type === "transfer.active" && "attempt_id" in data && identifier(data.attempt_id)) {
      return { type: "active", attemptId: data.attempt_id };
    }

    if (message.type === "transfer.acceptance_ready" && "attempt_id" in data && identifier(data.attempt_id)) {
      return { type: "acceptance_ready", attemptId: data.attempt_id };
    }

    if (message.type === "error" && "message" in data && typeof data.message === "string") {
      return { type: "error", message: data.message };
    }

    if (message.type === "transfer.progress" &&
      "attempt_id" in data && identifier(data.attempt_id) &&
      "phase" in data && member(progressPhases, data.phase) &&
      "blockers" in data && Array.isArray(data.blockers) &&
      data.blockers.length <= blockerKinds.length &&
      data.blockers.every((kind): kind is typeof blockerKinds[number] => member(blockerKinds, kind)) &&
      "elapsed_ms" in data && typeof data.elapsed_ms === "number" &&
      Number.isSafeInteger(data.elapsed_ms) && data.elapsed_ms >= 0
    ) {
      return { type: "progress", attemptId: data.attempt_id, phase: data.phase,
        blockers: data.blockers, elapsedMs: data.elapsed_ms };
    }
  } catch {
    return undefined;
  }

  return undefined;
}

function isAnswer(value: unknown): value is { pc_id: string; sdp: string; type: "answer" } {
  return (
    !!value &&
    typeof value === "object" &&
    "pc_id" in value &&
    identifier(value.pc_id) &&
    "sdp" in value &&
    typeof value.sdp === "string" &&
    "type" in value &&
    value.type === "answer"
  );
}

function acceptanceId(): string {
  if (typeof globalThis.crypto?.randomUUID === "function") {
    return `accept_${globalThis.crypto.randomUUID()}`;
  }

  return `accept_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 12)}`;
}

function identifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value);
}

function member<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === "string" && values.some((allowed) => allowed === value);
}
