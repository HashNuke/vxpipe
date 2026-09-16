import type { CallDetailsController, CallDetailsReader } from "./callDetails.js";

export interface LocalSessionSnapshot {
  connectionState: "ready" | "connecting" | "connected" | "failed";
  alignment: "word" | "segment" | "unavailable";
  microphone: "off" | "on" | "denied";
  speakerMuted: boolean;
  inputDevice: string;
  outputDevice: string;
  devices: {
    inputs: readonly string[];
    outputs: readonly string[];
    outputSelection: boolean;
  };
  notice?: string;
}

export interface LiveCallControls {
  getSnapshot(): LocalSessionSnapshot;
  subscribe(listener: () => void): () => void;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  sendText(text: string): Promise<void>;
  setMicrophone(enabled: boolean): Promise<void>;
  setSpeakerMuted(muted: boolean): Promise<void>;
  selectDevice(kind: "input" | "output", id: string): Promise<void>;
}

/** Host-composed boundary consumed by @vxpipe/react. */
export interface CallConsoleController {
  details: CallDetailsReader;
  history?: Pick<CallDetailsController, "refresh" | "loadOlder">;
  live?: LiveCallControls;
}
