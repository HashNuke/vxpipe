import { act, renderHook, waitFor } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import { editorFixture } from "./editorFixtures";
import type { EditorResult, EditorSnapshot } from "./editor-state";
import { useEditor, type ExecuteEditorRequest } from "./use-editor";

const snapshot: EditorSnapshot = { document: structuredClone(editorFixture), saved: { callSpecId: "appointments", revision: 3, publishedRevision: null } };
snapshot.document.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" } } };
function deferred() {
  let resolve!: (value: EditorResult) => void;
  const promise = new Promise<EditorResult>((done) => { resolve = done; });
  return { promise, resolve };
}

test("duplicate clicks send one exact snapshot and completion preserves newer edits", async () => {
  const request = deferred();
  const execute = vi.fn(() => request.promise);
  const { result } = renderHook(() => useEditor(snapshot, execute));
  act(() => { result.current.save(); result.current.save(); });
  expect(execute).toHaveBeenCalledTimes(1);
  expect(execute.mock.calls[0]).toEqual([{ id: 1, action: "save", source: snapshot.document.source, callSpecId: "appointments", revision: 3 }, expect.any(AbortSignal)]);
  act(() => result.current.edit({ ...snapshot.document, source: { ...snapshot.document.source, name: "New edit" } }));
  await act(async () => request.resolve({ status: 201, revision: 4 }));
  expect(result.current.state.document.source.name).toBe("New edit");
  expect(result.current.state.saved?.revision).toBe(4);
  expect(result.current.dirty).toBe(true);
});

test("client-blocked actions never reach the transport", () => {
  const execute = vi.fn();
  const { result } = renderHook(() => useEditor(snapshot, execute));
  act(() => result.current.edit({ ...snapshot.document, source: { ...snapshot.document.source, name: "x".repeat(257) } }));
  act(() => result.current.save());
  expect(execute).not.toHaveBeenCalled();
  expect(result.current.state.feedback.toast?.message).toBe("Fix 1 issue before saving");
});

test.each(["throw", "reject"])("a transport %s keeps edits and retry uses the latest draft", async (failure) => {
  const execute = vi.fn((): Promise<EditorResult> => {
    if (failure === "throw") throw new Error("Transport unavailable");
    return Promise.reject(new Error("Transport unavailable"));
  });
  const { result } = renderHook(() => useEditor(snapshot, execute));
  act(() => result.current.save());
  await waitFor(() => expect(result.current.state.feedback.toast?.action).toBe("retry"));
  execute.mockResolvedValue({ status: 201, revision: 4 });
  act(() => result.current.edit({ ...snapshot.document, source: { ...snapshot.document.source, name: "Retry this" } }));
  await act(async () => result.current.retry());
  expect(execute).toHaveBeenCalledTimes(2);
  expect(execute).toHaveBeenLastCalledWith(expect.objectContaining({ source: expect.objectContaining({ name: "Retry this" }) }), expect.any(AbortSignal));
  expect(result.current.dirty).toBe(false);
});

test("reload aborts pending work and ignores its late success", async () => {
  const request = deferred();
  const execute = vi.fn<ExecuteEditorRequest>(() => request.promise);
  const { result } = renderHook(() => useEditor(snapshot, execute));
  act(() => result.current.save());
  const signal = execute.mock.calls[0]![1];
  act(() => result.current.load({ ...snapshot, saved: { ...snapshot.saved!, revision: 8 } }));
  expect(signal.aborted).toBe(true);
  await act(async () => request.resolve({ status: 201, revision: 4 }));
  expect(result.current.state.saved?.revision).toBe(8);
  expect(result.current.state.feedback.toast).toBeNull();
});

test("unmount aborts a publish save; late success cannot publish or redirect", async () => {
  const request = deferred();
  const execute = vi.fn<ExecuteEditorRequest>(() => request.promise);
  const expired = vi.fn();
  const { result, unmount } = renderHook(() => useEditor({ document: snapshot.document }, execute, expired));
  act(() => result.current.publish());
  unmount();
  expect(execute.mock.calls[0]![1].aborted).toBe(true);
  await act(async () => request.resolve({ status: 201, callSpecId: "created", revision: 1 }));
  expect(expired).not.toHaveBeenCalled();
  expect(execute).toHaveBeenCalledTimes(1);
});

test("session expiry notifies the host once and keeps the draft available", async () => {
  const execute = vi.fn(async () => ({ status: 401 }));
  const expired = vi.fn();
  const { result } = renderHook(() => useEditor(snapshot, execute, expired));
  act(() => result.current.edit({ ...snapshot.document, source: { ...snapshot.document.source, name: "Retain me" } }));
  await act(async () => result.current.save());
  act(() => result.current.save());
  expect(expired).toHaveBeenCalledTimes(1);
  expect(execute).toHaveBeenCalledTimes(1);
  expect(result.current.state.document.source.name).toBe("Retain me");
});

test("invalid-request defects are logged without source or backend reason text", async () => {
  const log = vi.spyOn(console, "error").mockImplementation(() => {});
  try {
    const execute = vi.fn(async () => ({ status: 400, error: { code: "invalid_request", reason: "Do not log backend payloads" } }));
    const { result } = renderHook(() => useEditor(snapshot, execute));
    await act(async () => result.current.save());
    expect(log).toHaveBeenCalledExactlyOnceWith("Call spec editor sent an invalid request.", { action: "save" });
  } finally { log.mockRestore(); }
});

test("Publish saves the clicked draft then publishes its returned revision, preserving subsequent edits", async () => {
  const save = deferred();
  const execute = vi.fn<ExecuteEditorRequest>().mockImplementationOnce(() => save.promise).mockResolvedValueOnce({ status: 200, revision: 4 });
  const { result } = renderHook(() => useEditor(snapshot, execute));
  act(() => result.current.edit({ ...snapshot.document, source: { ...snapshot.document.source, opening_audio: { type: "text", text: "Welcome.", text_to_speech: { provider: "elevenlabs", model: "eleven_flash_v2_5", credential_name: "elevenlabs" } } } }));
  act(() => { result.current.publish(); result.current.publish(); });
  expect(execute).toHaveBeenCalledTimes(1);
  expect(execute.mock.calls[0]![0]).toMatchObject({ action: "save", source: { opening_audio: { text: "Welcome." } } });
  act(() => result.current.edit({ ...result.current.state.document, source: { ...result.current.state.document.source, name: "Next draft" } }));
  await act(async () => save.resolve({ status: 201, revision: 4 }));
  await waitFor(() => expect(result.current.state.saved?.publishedRevision).toBe(4));
  expect(execute.mock.calls[1]![0]).toMatchObject({ action: "publish", callSpecId: "appointments", revision: 4, source: { name: snapshot.document.source.name } });
  expect(result.current.state.document.source.name).toBe("Next draft");
  expect(result.current.dirty).toBe(true);
});

test.each([{}, { status: 422 }, { status: 201 }])("failed or malformed save never advances to publication: %j", async failure => {
  const execute = vi.fn<ExecuteEditorRequest>().mockResolvedValue(failure);
  const { result } = renderHook(() => useEditor({ document: snapshot.document }, execute));
  await act(async () => result.current.publish());
  expect(execute).toHaveBeenCalledTimes(1);
  expect(result.current.state.saved).toBeUndefined();
  expect(result.current.dirty).toBe(true);
});

test("Publish on a new spec uses its assigned server identity", async () => {
  const execute = vi.fn<ExecuteEditorRequest>().mockResolvedValueOnce({ status: 201, callSpecId: "created", revision: 1 }).mockResolvedValueOnce({ status: 200, callSpecId: "created", revision: 1 });
  const { result } = renderHook(() => useEditor({ document: snapshot.document }, execute));
  await act(async () => result.current.publish());
  expect(execute.mock.calls.map(([request]) => request.action)).toEqual(["save", "publish"]);
  expect(result.current.state.saved).toEqual({ callSpecId: "created", revision: 1, publishedRevision: 1 });
});
