import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { useWaitSoundPreview } from "./wait-sound-preview";

function Harness() {
  const preview = useWaitSoundPreview();
  return <>
    <button onClick={() => preview.toggle("one", "https://example.test/one.wav")}>One</button>
    <button onClick={() => preview.toggle("two", "https://example.test/two.wav")}>Two</button>
    <button onClick={preview.stop}>Stop</button>
    <output>{preview.active}</output>
    <span data-testid="state">{preview.state}</span>
    <span data-testid="progress">{preview.progress}</span>
    {preview.error && <p role="alert">{preview.error.message}</p>}
  </>;
}
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

test("previews never overlap, can stop, and release playback on unmount", async () => {
  const played: HTMLMediaElement[] = [];
  vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(function (this: HTMLMediaElement) { played.push(this); return Promise.resolve(); });
  const pause = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  const { unmount } = render(<Harness />);
  fireEvent.click(screen.getByText("One"));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("one"));
  fireEvent.click(screen.getByText("Two"));
  expect(pause).toHaveBeenCalledTimes(1);
  expect(played[0]!.getAttribute("src")).toBeNull();
  fireEvent.click(screen.getByText("Two"));
  expect(screen.getByRole("status")).toHaveTextContent("two");
  expect(screen.getByTestId("state")).toHaveTextContent("paused");
  expect(pause).toHaveBeenCalledTimes(2);
  fireEvent.click(screen.getByText("One"));
  unmount();
  expect(pause).toHaveBeenCalledTimes(4);
});

test("failed playback is recoverable and stale failures cannot replace the active preview", async () => {
  let rejectOld!: (error: Error) => void;
  const play = vi.spyOn(HTMLMediaElement.prototype, "play")
    .mockImplementationOnce(() => new Promise((_, reject) => { rejectOld = reject; }))
    .mockRejectedValueOnce(new Error("unavailable"))
    .mockResolvedValue(undefined);
  vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  render(<Harness />);
  fireEvent.click(screen.getByText("One"));
  fireEvent.click(screen.getByText("Stop"));
  await act(async () => rejectOld(new Error("cancelled")));
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  fireEvent.click(screen.getByText("Two"));
  expect(await screen.findByRole("alert")).toHaveTextContent("Couldn’t play");
  expect(screen.getByRole("status")).toBeEmptyDOMElement();
  fireEvent.click(screen.getByText("Two"));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("two"));
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  expect(play).toHaveBeenCalledTimes(3);
});


test("pause preserves progress and resume reuses the player until the audio ends", async () => {
  const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
  vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  render(<Harness />);
  fireEvent.click(screen.getByText("One"));
  await waitFor(() => expect(screen.getByTestId("state")).toHaveTextContent("playing"));
  const player = play.mock.contexts[0];
  if (!(player instanceof HTMLMediaElement)) throw new Error("Expected audio player");
  Object.defineProperty(player, "duration", { value: 10, configurable: true });
  player.currentTime = 4;
  fireEvent.timeUpdate(player);
  expect(screen.getByTestId("progress")).toHaveTextContent("0.4");
  fireEvent.click(screen.getByText("One"));
  expect(screen.getByTestId("state")).toHaveTextContent("paused");
  expect(player.currentTime).toBe(4);
  fireEvent.click(screen.getByText("One"));
  await waitFor(() => expect(screen.getByTestId("state")).toHaveTextContent("playing"));
  expect(play.mock.instances[1]).toBe(player);
  expect(player.currentTime).toBe(4);
  fireEvent.ended(player);
  expect(screen.getByTestId("state")).toHaveTextContent("idle");
  expect(screen.getByTestId("progress")).toHaveTextContent("0");
});

test("loading, buffering, and unknown duration do not invent progress", async () => {
  let resolvePlay!: () => void;
  const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(() => {
    return new Promise((resolve) => { resolvePlay = resolve; });
  });
  vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  render(<Harness />);
  fireEvent.click(screen.getByText("One"));
  expect(screen.getByTestId("state")).toHaveTextContent("loading");
  const player = play.mock.contexts[0];
  if (!(player instanceof HTMLMediaElement)) throw new Error("Expected audio player");
  Object.defineProperty(player, "duration", { value: Infinity });
  player.currentTime = 4;
  fireEvent.timeUpdate(player);
  expect(screen.getByTestId("progress")).toHaveTextContent("0");
  await act(async () => resolvePlay());
  expect(screen.getByTestId("state")).toHaveTextContent("playing");
  fireEvent.waiting(player);
  expect(screen.getByTestId("state")).toHaveTextContent("loading");
  fireEvent.playing(player);
  expect(screen.getByTestId("state")).toHaveTextContent("playing");
});
