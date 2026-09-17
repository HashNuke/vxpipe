import { useState } from "react";
import type { LiveCallControls } from "@vxpipe/core";
import type { ConsoleSnapshot } from "./types.js";
import { DeviceMenu } from "./DeviceMenu.js";
import { Icon } from "./Icon.js";

export function DeviceControls({
  snapshot,
  controls,
  theme = "dark",
}: {
  snapshot: ConsoleSnapshot;
  controls: LiveCallControls;
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
        <div className="vx-device-group" role="group" aria-label="Input audio">
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
              void act(() => controls.setMicrophone(snapshot.microphone !== "on"))
            }
          >
            <Icon name="mic" />
            {snapshot.microphone !== "on" && (
              <span className="vx-mute-slash" aria-hidden="true" />
            )}
          </button>
          <DeviceMenu
            devices={snapshot.devices.inputs}
            disabled={!active || snapshot.microphone === "denied"}
            label="Input device"
            onSelect={(value) =>
              void act(() => controls.selectDevice("input", value))
            }
            theme={theme}
            value={snapshot.inputDevice}
          />
        </div>
        <div className="vx-device-group" role="group" aria-label="Output audio">
          <button
            className="vx-button vx-icon-button"
            aria-label={
              snapshot.speakerMuted ? "Unmute speaker" : "Mute speaker"
            }
            aria-pressed={snapshot.speakerMuted}
            title={snapshot.speakerMuted ? "Unmute speaker" : "Mute speaker"}
            onClick={() =>
              void act(() => controls.setSpeakerMuted(!snapshot.speakerMuted))
            }
          >
            <Icon name="speaker" />
            {snapshot.speakerMuted && (
              <span className="vx-mute-slash" aria-hidden="true" />
            )}
          </button>
          <DeviceMenu
            devices={snapshot.devices.outputs}
            disabled={!snapshot.devices.outputSelection}
            label="Output device"
            onSelect={(value) =>
              void act(() => controls.selectDevice("output", value))
            }
            theme={theme}
            value={snapshot.outputDevice}
          />
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
