import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CopyButton } from "./CopyButton";

afterEach(() => { cleanup(); vi.useRealTimers(); vi.restoreAllMocks(); });

function clipboard(writeText = vi.fn().mockResolvedValue(undefined)) {
  Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } });
  return writeText;
}

test("copies the value and briefly confirms each successful click in the button", async () => {
  vi.useFakeTimers();
  const writeText = clipboard();
  render(<CopyButton value="example" label="Copy API key" />);
  const button = screen.getByRole("button", { name: "Copy API key" });
  await act(async () => fireEvent.click(button));
  expect(writeText).toHaveBeenCalledWith("example");
  expect(button).toHaveTextContent("Copied");
  act(() => vi.advanceTimersByTime(1500));
  await act(async () => fireEvent.click(button));
  act(() => vi.advanceTimersByTime(1500));
  expect(button).toHaveTextContent("Copied");
  act(() => vi.advanceTimersByTime(500));
  expect(button).toHaveTextContent("Copy API key");
});

test("failed copying offers manual recovery and retry clears the error", async () => {
  const writeText = clipboard(vi.fn().mockRejectedValueOnce(new Error("denied")).mockResolvedValue(undefined));
  render(<CopyButton value="example" />);
  const button = screen.getByRole("button", { name: "Copy" });
  await act(async () => fireEvent.click(button));
  expect(screen.getByRole("alert")).toHaveTextContent("Copy failed. Select the value and copy it manually.");
  expect(button).not.toHaveTextContent("Copied");
  await act(async () => fireEvent.click(button));
  expect(writeText).toHaveBeenCalledTimes(2);
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  expect(button).toHaveTextContent("Copied");
});

test("a pending copy cannot confirm a replaced value or leave a reset timer after unmount", async () => {
  vi.useFakeTimers();
  let resolve!: () => void;
  clipboard(vi.fn(() => new Promise<void>(done => { resolve = done; })));
  const { rerender, unmount } = render(<CopyButton value="old" />);
  fireEvent.click(screen.getByRole("button", { name: "Copy" }));
  expect(screen.getByRole("button", { name: "Copy" })).toBeDisabled();
  rerender(<CopyButton value="new" />);
  await act(async () => resolve());
  expect(screen.getByRole("button", { name: "Copy" })).not.toHaveTextContent("Copied");
  unmount();
  expect(vi.getTimerCount()).toBe(0);
});
