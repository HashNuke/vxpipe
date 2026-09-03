import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";

vi.mock("@pipecat-ai/voice-ui-kit", () => ({
  ConsoleTemplate: ({
    connectParams,
    titleText,
    transportType,
  }: {
    connectParams: { webrtcUrl: string };
    titleText: string;
    transportType: string;
  }) => (
    <section
      aria-label="RTVI console"
      data-transport={transportType}
      data-webrtc-url={connectParams.webrtcUrl}
    >
      {titleText}
    </section>
  ),
}));

import App from "./App";

test("configures the Pipecat console for the Vxpipe RTVI gateway", () => {
  render(<App />);

  const console = screen.getByRole("region", { name: "RTVI console" });

  expect(console).toHaveTextContent("Vxpipe RTVI Playground");
  expect(console).toHaveAttribute("data-transport", "smallwebrtc");
  expect(console).toHaveAttribute("data-webrtc-url", "/api/rtvi/offer");
});
