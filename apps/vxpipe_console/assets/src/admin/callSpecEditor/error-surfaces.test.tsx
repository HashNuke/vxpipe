import { useState } from "react";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { EditorToast } from "./editor-toast";
import { IssuesDrawer } from "./issues-drawer";
import { SourceView } from "./source-view";
import { editorFixture } from "./editorFixtures";
import type { SourceIssue } from "./types";
afterEach(() => { cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });
const issue: SourceIssue = { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "Prompt is required" };
test("the issues drawer lists operator locations and delegates Show without changing source", () => {
  const show = vi.fn();
  render(<IssuesDrawer open onOpenChange={vi.fn()} source={editorFixture.source} issues={[issue, { ...issue, path: ["future"], reason: "Unknown setting" }]} onShow={show} />);
  expect(screen.getByRole("dialog", { name: "Call spec issues" })).toBeInTheDocument();
  expect(screen.getByText("Agent intake › Prompt")).toBeInTheDocument();
  fireEvent.click(screen.getAllByRole("button", { name: "Show" })[0]!);
  expect(show).toHaveBeenCalledWith(issue);
  expect(screen.getByText("Unknown setting")).toBeInTheDocument();
});
test("one replaceable toast exposes recovery actions; only success auto-dismisses", () => {
  vi.useFakeTimers();
  const dismiss = vi.fn(); const action = vi.fn();
  const { rerender } = render(<EditorToast feedback={{ tone: "error", message: "Could not save", persistent: true, action: "retry" }} onAction={action} onDismiss={dismiss} />);
  fireEvent.click(screen.getByRole("button", { name: "Retry" })); expect(action).toHaveBeenCalledWith("retry");
  act(() => vi.advanceTimersByTime(10000)); expect(dismiss).not.toHaveBeenCalled();
  rerender(<EditorToast feedback={{ tone: "success", message: "Saved as revision 4", persistent: false }} onAction={action} onDismiss={dismiss} />);
  expect(screen.queryByText("Could not save")).not.toBeInTheDocument();
  act(() => vi.advanceTimersByTime(6000)); expect(dismiss).toHaveBeenCalledOnce();
});
test("Show, Open services and Reload actions retain their meaning", () => {
  const action = vi.fn();
  const { rerender } = render(<EditorToast feedback={null} onAction={action} onDismiss={vi.fn()} />);
  for (const [kind, label] of [["show", "Show"], ["services", "Open services"], ["reload", "Reload"]] as const) {
    rerender(<EditorToast feedback={{ tone: "error", message: "Action failed", persistent: true, action: kind }} onAction={action} onDismiss={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: label })); expect(action).toHaveBeenLastCalledWith(kind);
  }
});
test("source view is read-only and copies and downloads the exact portable source", async () => {
  const copy = vi.fn().mockResolvedValue(undefined); const feedback = vi.fn();
  Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: copy } });
  const create = vi.fn<(blob: Blob) => string>(() => "blob:test"); const revoke = vi.fn();
  vi.stubGlobal("URL", { createObjectURL: create, revokeObjectURL: revoke });
  const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  render(<SourceView open onOpenChange={vi.fn()} source={editorFixture.source} onFeedback={feedback} />);
  const text = JSON.stringify(editorFixture.source, null, 2);
  expect(screen.getByRole("textbox", { name: "Call spec JSON" })).toHaveValue(text);
  expect(screen.getByRole("textbox", { name: "Call spec JSON" })).toHaveAttribute("readonly");
  fireEvent.click(screen.getByRole("button", { name: "Copy JSON" }));
  await waitFor(() => expect(copy).toHaveBeenCalledWith(text));
  fireEvent.click(screen.getByRole("button", { name: "Download JSON" }));
  expect(create.mock.calls[0]?.[0]).toBeInstanceOf(Blob);
  expect(click).toHaveBeenCalledOnce(); expect(revoke).toHaveBeenCalledWith("blob:test");
});
test("clipboard failure becomes an action failure with source retained", async () => {
  Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: vi.fn().mockRejectedValue(new Error("denied")) } });
  const feedback = vi.fn();
  render(<SourceView open onOpenChange={vi.fn()} source={editorFixture.source} onFeedback={feedback} />);
  fireEvent.click(screen.getByRole("button", { name: "Copy JSON" }));
  await waitFor(() => expect(feedback).toHaveBeenCalledWith(expect.objectContaining({ tone: "error", persistent: true })));
  expect(screen.getByRole("textbox", { name: "Call spec JSON" })).toHaveValue(JSON.stringify(editorFixture.source, null, 2));
});

test("an unmappable Show keeps the drawer open and Close restores its opener", async () => {
  function Harness() {
    const [open, setOpen] = useState(false);
    return <><button onClick={() => setOpen(true)}>Open issues</button><IssuesDrawer open={open} onOpenChange={setOpen} source={editorFixture.source} issues={[{ ...issue, path: ["future"] }]} onShow={() => setOpen(true)} /></>;
  }
  render(<Harness />);
  const opener = screen.getByRole("button", { name: "Open issues" }); opener.focus(); fireEvent.click(opener);
  fireEvent.click(screen.getByRole("button", { name: "Show" }));
  expect(screen.getByRole("dialog")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  await waitFor(() => expect(opener).toHaveFocus());
});

test("closing source inspection restores the View JSON button", async () => {
  function Harness() {
    const [open, setOpen] = useState(false);
    return <><button onClick={() => setOpen(true)}>View JSON</button><SourceView open={open} onOpenChange={setOpen} source={editorFixture.source} onFeedback={vi.fn()} /></>;
  }
  render(<Harness />);
  const opener = screen.getByRole("button", { name: "View JSON" }); opener.focus(); fireEvent.click(opener);
  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  await waitFor(() => expect(opener).toHaveFocus());
});
