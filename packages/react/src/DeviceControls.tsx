import { useState } from "react";
import type { CallSnapshot, VxpipeClient } from "@vxpipe/core";
import { Icon } from "./Icon.js";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./Select.js";

export function DeviceControls({
  snapshot,
  client,
  theme = "dark",
}: {
  snapshot: CallSnapshot;
  client: VxpipeClient;
  theme?: "light" | "dark";
}) {
  const [error, setError] = useState("");
  const active = snapshot.state === "connected";
  const act = async (operation: () => Promise<void>) => {
    setError("");
    try {
      await operation();
    } catch {
      setError("Device change failed. Check device permissions and try again.");
    }
  };
  return (
    <div className="vx-devices">
      <div className="vx-device-row">
        <div className="vx-device-group">
          <button
            className="vx-button vx-icon-button"
            aria-label={
              snapshot.microphone === "on"
                ? "Mute microphone"
                : "Enable microphone"
            }
            aria-pressed={snapshot.microphone === "on"}
            title={
              snapshot.microphone === "on"
                ? "Mute microphone"
                : "Enable microphone"
            }
            disabled={!active || snapshot.microphone === "denied"}
            onClick={() =>
              void act(() => client.setMicrophone(snapshot.microphone !== "on"))
            }
          >
            <Icon name="mic" />
            {snapshot.microphone !== "on" && (
              <span className="vx-mute-slash" aria-hidden="true" />
            )}
          </button>
          <Select
            disabled={!active || snapshot.microphone === "denied"}
            value={snapshot.inputDevice}
            onValueChange={(value) =>
              void act(() => client.selectDevice("input", value))
            }
          >
            <SelectTrigger aria-label="Input device">
              <SelectValue />
            </SelectTrigger>
            <SelectContent theme={theme}>
              {snapshot.devices.inputs.map((device) => (
                <SelectItem key={device} value={device}>
                  {device}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="vx-device-group">
          <button
            className="vx-button vx-icon-button"
            aria-label={
              snapshot.speakerMuted ? "Unmute speaker" : "Mute speaker"
            }
            aria-pressed={snapshot.speakerMuted}
            title={snapshot.speakerMuted ? "Unmute speaker" : "Mute speaker"}
            onClick={() =>
              void act(() => client.setSpeakerMuted(!snapshot.speakerMuted))
            }
          >
            <Icon name="speaker" />
            {snapshot.speakerMuted && (
              <span className="vx-mute-slash" aria-hidden="true" />
            )}
          </button>
          <Select
            disabled={!snapshot.devices.outputSelection}
            value={snapshot.outputDevice}
            onValueChange={(value) =>
              void act(() => client.selectDevice("output", value))
            }
          >
            <SelectTrigger aria-label="Output device">
              <SelectValue />
            </SelectTrigger>
            <SelectContent theme={theme}>
              {snapshot.devices.outputs.map((device) => (
                <SelectItem key={device} value={device}>
                  {device}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
      {snapshot.microphone === "denied" && (
        <p>Microphone access is blocked. You can still type.</p>
      )}
      {!snapshot.devices.outputSelection && (
        <p>This browser uses your system output device.</p>
      )}
      {error && (
        <p className="vx-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
