import { afterEach, expect, test, vi } from "vitest";

import type { GatewaySession } from "./sampleAdmission";
import { openTransferConnection } from "./transferConnection";

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

test("negotiates the sideband peer, projects controls, and releases browser media", async () => {
  const send = vi.fn();
  const closeChannel = vi.fn();
  const dataChannel = {
    readyState: "open",
    send,
    close: closeChannel,
    onmessage: null as ((event: MessageEvent) => void) | null,
  };

  const stopMicrophone = vi.fn();
  const microphone = {
    getTracks: () => [{ stop: stopMicrophone }],
  } as unknown as MediaStream;

  const remoteStream = {} as MediaStream;
  const play = vi.fn().mockResolvedValue(undefined);
  const pause = vi.fn();
  const audio = { autoplay: false, srcObject: null, play, pause };

  const peer = {
    localDescription: undefined as RTCSessionDescriptionInit | undefined,
    connectionState: "new",
    onicecandidate: null as ((event: RTCPeerConnectionIceEvent) => void) | null,
    onconnectionstatechange: null as (() => void) | null,
    ontrack: null as ((event: RTCTrackEvent) => void) | null,
    createDataChannel: vi.fn(() => dataChannel),
    addTrack: vi.fn(),
    createOffer: vi.fn().mockResolvedValue({ type: "offer", sdp: "offer-sdp" }),
    setLocalDescription: vi.fn(async (description: RTCSessionDescriptionInit) => {
      peer.localDescription = description;
    }),
    setRemoteDescription: vi.fn().mockResolvedValue(undefined),
    close: vi.fn(),
  };

  const PeerConnectionConstructor = vi.fn(function () {
    return peer;
  });
  const AudioConstructor = vi.fn(function () {
    return audio;
  });
  const MediaStreamConstructor = vi.fn(function () {
    return remoteStream;
  });

  vi.stubGlobal("RTCPeerConnection", PeerConnectionConstructor);
  vi.stubGlobal("navigator", { mediaDevices: { getUserMedia: vi.fn().mockResolvedValue(microphone) } });
  vi.stubGlobal("Audio", AudioConstructor);
  vi.stubGlobal("MediaStream", MediaStreamConstructor);

  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    json: async () => ({ pc_id: "conn_support", type: "answer", sdp: "answer-sdp" }),
  });
  vi.stubGlobal("fetch", fetchMock);

  const onControl = vi.fn();
  const onClosed = vi.fn();
  const onInterrupted = vi.fn();

  const session: GatewaySession = {
    session_id: "sess_support",
    expires_at: "2026-09-11T08:35:00Z",
    transport: {
      type: "smallwebrtc",
      endpoint: "",
      request_data: { session_id: "sess_support" },
    },
  };

  const connection = await openTransferConnection(session, { onControl, onClosed, onInterrupted });

  expect(peer.createDataChannel).toHaveBeenCalledWith("vxpipe", { ordered: true });
  expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/rtvi/offer", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      sdp: "offer-sdp",
      type: "offer",
      pc_id: null,
      restart_pc: false,
      requestData: { session_id: "sess_support" },
    }),
  });
  expect(peer.setRemoteDescription).toHaveBeenCalledWith({ type: "answer", sdp: "answer-sdp" });

  const candidate = {
    candidate: "candidate:1 1 UDP 1 192.0.2.1 4000 typ host",
    sdpMid: "0",
    sdpMLineIndex: 0,
  } as RTCIceCandidate;

  peer.onicecandidate?.({ candidate } as RTCPeerConnectionIceEvent);

  await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/rtvi/offer", {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      pc_id: "conn_support",
      candidates: [
        {
          candidate: candidate.candidate,
          sdp_mid: candidate.sdpMid,
          sdp_mline_index: candidate.sdpMLineIndex,
        },
      ],
    }),
  });

  dataChannel.onmessage?.(
    new MessageEvent("message", {
      data: JSON.stringify({
        id: "xfer_demo",
        type: "transfer.preparation",
        data: { attempt_id: "xfer_demo", participant_id: "part_support" },
      }),
    }),
  );

  expect(onControl).toHaveBeenCalledWith({
    type: "preparation",
    attemptId: "xfer_demo",
    participantId: "part_support",
  });

  dataChannel.onmessage?.(
    new MessageEvent("message", {
      data: JSON.stringify({
        id: "xfer_demo",
        type: "transfer.acceptance_ready",
        data: { attempt_id: "xfer_demo" },
      }),
    }),
  );

  expect(onControl).toHaveBeenCalledWith({ type: "acceptance_ready", attemptId: "xfer_demo" });

  dataChannel.onmessage?.(new MessageEvent("message", {data: JSON.stringify({
    type: "transfer.progress", data: {attempt_id: "xfer_demo", phase: "preparing", blockers: ["speech_to_text"], elapsed_ms: 250},
  })}));
  expect(onControl).toHaveBeenLastCalledWith({type: "progress", attemptId: "xfer_demo", phase: "preparing", blockers: ["speech_to_text"], elapsedMs: 250});

  const controlCount = onControl.mock.calls.length;
  for (const data of [
    {attempt_id: "xfer_demo", phase: "provider-secret", blockers: [], elapsed_ms: 1},
    {attempt_id: "xfer_demo", phase: "preparing", blockers: ["https://private.example/audio?token=secret"], elapsed_ms: 1},
    {attempt_id: "xfer_demo", phase: "preparing", blockers: [], elapsed_ms: -1},
  ]) {
    dataChannel.onmessage?.(new MessageEvent("message", {data: JSON.stringify({type: "transfer.progress", data})}));
  }
  expect(onControl).toHaveBeenCalledTimes(controlCount);

  connection.accept("xfer_demo");
  expect(JSON.parse(send.mock.calls[0][0])).toMatchObject({
    type: "transfer.accept",
    data: { attempt_id: "xfer_demo" },
  });

  peer.ontrack?.({ streams: [remoteStream] } as unknown as RTCTrackEvent);
  expect(audio.srcObject).toBe(remoteStream);
  expect(audio.autoplay).toBe(true);
  expect(play).toHaveBeenCalledOnce();

  peer.connectionState = "disconnected";
  peer.onconnectionstatechange?.();
  expect(onInterrupted).toHaveBeenLastCalledWith(true);
  expect(onClosed).not.toHaveBeenCalled();
  expect(peer.close).not.toHaveBeenCalled();

  peer.connectionState = "connected";
  peer.onconnectionstatechange?.();
  expect(onInterrupted).toHaveBeenLastCalledWith(false);

  peer.connectionState = "closed";
  peer.onconnectionstatechange?.();
  expect(onClosed).toHaveBeenCalledOnce();

  connection.close();
  expect(stopMicrophone).toHaveBeenCalledOnce();
  expect(closeChannel).toHaveBeenCalledOnce();
  expect(peer.close).toHaveBeenCalledOnce();
  expect(pause).toHaveBeenCalledOnce();
});
