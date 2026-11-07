import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { SetupDialog } from "./SetupDialog";

afterEach(cleanup);
const pointer = { pointerId: 1, isPrimary: true, button: 0 };

test("a gesture beginning inside does not dismiss after reflow puts release on the backdrop", () => {
  const onClose = vi.fn();
  render(<SetupDialog title="Manage connection" onClose={onClose}><button>Change panel</button></SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(screen.getByRole("button", { name: "Change panel" }), pointer);
  fireEvent.pointerUp(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
});

test("a genuine backdrop gesture closes once and is consumed", () => {
  const onClose = vi.fn();
  render(<SetupDialog title="Manage connection" onClose={onClose}>Settings</SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(backdrop, pointer);
  fireEvent.pointerUp(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).toHaveBeenCalledTimes(1);
  fireEvent.click(backdrop);
  expect(onClose).toHaveBeenCalledTimes(1);
});

test("cancelled backdrop gestures do not dismiss and a fresh gesture still works", () => {
  const onClose = vi.fn();
  render(<SetupDialog title="Manage connection" onClose={onClose}>Settings</SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(backdrop, pointer);
  fireEvent.pointerCancel(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
  fireEvent.pointerDown(backdrop, pointer);
  fireEvent.pointerUp(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).toHaveBeenCalledTimes(1);
});

test("a backdrop gesture released over dialog content does not dismiss", () => {
  const onClose = vi.fn();
  render(<SetupDialog title="Manage connection" onClose={onClose}><button>Keep editing</button></SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(backdrop, pointer);
  fireEvent.pointerUp(screen.getByRole("button", { name: "Keep editing" }), pointer);
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
});

test("another pointer cannot complete the original backdrop gesture", () => {
  const onClose = vi.fn();
  render(<SetupDialog title="Manage connection" onClose={onClose}>Settings</SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(backdrop, pointer);
  fireEvent.pointerDown(backdrop, { ...pointer, pointerId: 2, isPrimary: false });
  fireEvent.pointerUp(backdrop, { ...pointer, pointerId: 2, isPrimary: false });
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
});

test("a gesture begun while busy cannot close after the operation completes", () => {
  const onClose = vi.fn();
  const { rerender } = render(<SetupDialog title="Manage connection" onClose={onClose} busy>Settings</SetupDialog>);
  const backdrop = screen.getByRole("dialog").parentElement!;
  fireEvent.pointerDown(backdrop, pointer);
  rerender(<SetupDialog title="Manage connection" onClose={onClose}>Settings</SetupDialog>);
  fireEvent.pointerUp(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
});

test("explicit close and Escape retain their busy guards", () => {
  const onClose = vi.fn();
  const { rerender } = render(<SetupDialog title="Manage connection" onClose={onClose} busy>Settings</SetupDialog>);
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  expect(screen.getByRole("button", { name: "Close dialog" })).toBeDisabled();
  expect(onClose).not.toHaveBeenCalled();
  rerender(<SetupDialog title="Manage connection" onClose={onClose}>Settings</SetupDialog>);
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  expect(onClose).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: "Close dialog" }));
  expect(onClose).toHaveBeenCalledTimes(2);
});
