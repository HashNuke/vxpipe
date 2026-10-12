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
  expect(screen.getByRole("status")).toBeEmptyDOMElement();
  expect(pause).toHaveBeenCalledTimes(2);
  fireEvent.click(screen.getByText("One"));
  unmount();
  expect(pause).toHaveBeenCalledTimes(3);
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
