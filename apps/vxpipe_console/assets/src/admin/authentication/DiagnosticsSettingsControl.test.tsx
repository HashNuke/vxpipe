import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { DiagnosticsSettingsFixture } from "./DiagnosticsSettingsFixture";
import { DiagnosticsSettingsControl } from "./DiagnosticsSettingsControl";
import { AuthenticationError } from "./authenticationApi";

afterEach(cleanup);
const off = { enabled: false, revision: 0 };
const label = "Benchmark using Silero VAD";

test("keeps the saved value until persistence succeeds and distinguishes unknown collection status", async () => {
  let finish!: (value: { enabled: boolean; revision: number }) => void;
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue(off), updateDiagnosticsSettings: vi.fn(() => new Promise<{ enabled: boolean; revision: number }>(resolve => { finish = resolve; })) };
  render(<DiagnosticsSettingsControl api={api} />);
  const toggle = await screen.findByRole("checkbox", { name: label });
  expect(toggle).not.toBeChecked();
  fireEvent.click(toggle);
  expect(toggle).not.toBeChecked();
  expect(toggle).toBeDisabled();
  expect(api.updateDiagnosticsSettings).toHaveBeenCalledWith(true, 0);
  finish({ enabled: true, revision: 1 });
  await waitFor(() => expect(toggle).toBeChecked());
  expect(screen.getByText(/Collection status unavailable/)).toBeVisible();
});

test("failed saves preserve the last confirmed value and allow retry after reload", async () => {
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue(off), updateDiagnosticsSettings: vi.fn().mockRejectedValueOnce(new Error("Network unavailable")).mockResolvedValue({ enabled: true, revision: 1 }) };
  render(<DiagnosticsSettingsControl api={api} />);
  const toggle = await screen.findByRole("checkbox", { name: label });
  fireEvent.click(toggle);
  await screen.findByRole("alert");
  expect(toggle).not.toBeChecked();
  expect(toggle).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Reload diagnostics settings" }));
  fireEvent.click(await screen.findByRole("checkbox", { name: label }));
  await waitFor(() => expect(screen.getByRole("checkbox")).toBeChecked());
});

test("a lost save response offers reconciliation instead of claiming the setting did not change", async () => {
  let persisted = off;
  const api = {
    diagnosticsSettings: vi.fn(async () => persisted),
    updateDiagnosticsSettings: vi.fn(async () => {
      persisted = { enabled: true, revision: 1 };
      throw new TypeError("Network connection closed after the server committed");
    }),
  };
  render(<DiagnosticsSettingsControl api={api} />);
  fireEvent.click(await screen.findByRole("checkbox", { name: label }));
  const alert = await screen.findByRole("alert");
  expect(persisted.enabled).toBe(true);
  expect(alert).not.toHaveTextContent("Your saved setting has not changed");
  fireEvent.click(screen.getByRole("button", { name: "Reload diagnostics settings" }));
  await waitFor(() => expect(screen.getByRole("checkbox")).toBeChecked());
  expect(api.updateDiagnosticsSettings).toHaveBeenCalledOnce();
});

test("conflicts require a reload before another save", async () => {
  const api = { diagnosticsSettings: vi.fn().mockResolvedValueOnce(off).mockResolvedValue({ enabled: true, revision: 4 }), updateDiagnosticsSettings: vi.fn().mockRejectedValue(new AuthenticationError("Conflict", 409, "conflict")) };
  render(<DiagnosticsSettingsControl api={api} />);
  fireEvent.click(await screen.findByRole("checkbox", { name: label }));
  await screen.findByRole("alert");
  expect(screen.getByRole("checkbox")).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Reload diagnostics settings" }));
  await waitFor(() => expect(screen.getByRole("checkbox")).toBeChecked());
  expect(screen.getByRole("checkbox")).toBeEnabled();
});

test("load failures offer retry without inventing an off value", async () => {
  const api = { diagnosticsSettings: vi.fn().mockRejectedValueOnce(new Error("Unavailable")).mockResolvedValue(off), updateDiagnosticsSettings: vi.fn() };
  render(<DiagnosticsSettingsControl api={api} />);
  await screen.findByRole("alert");
  expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Reload diagnostics settings" }));
  expect(await screen.findByRole("checkbox", { name: label })).not.toBeChecked();
});


test("applying status refreshes until the server confirms it is applied", async () => {
  vi.useFakeTimers();
  const api = { diagnosticsSettings: vi.fn().mockResolvedValueOnce({ ...off, collection_status: "applying" }).mockResolvedValue({ ...off, collection_status: "applied" }), updateDiagnosticsSettings: vi.fn() };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    expect(screen.getByText(/Applying setting/)).toBeVisible();
    await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    expect(screen.getByText(/Setting applied/)).toBeVisible();
    await act(async () => { await vi.advanceTimersByTimeAsync(20000); });
    expect(api.diagnosticsSettings).toHaveBeenCalledTimes(2);
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("an older status reply cannot replace a newer save", async () => {
  vi.useFakeTimers();
  let finish!: (value: typeof off) => void;
  const api = { diagnosticsSettings: vi.fn().mockResolvedValueOnce({ ...off, collection_status: "applying" }).mockImplementation(() => new Promise(resolve => { finish = resolve; })), updateDiagnosticsSettings: vi.fn().mockResolvedValue({ enabled: true, revision: 1 }) };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    fireEvent.click(screen.getByRole("checkbox"));
    await act(async () => {});
    await act(async () => { finish(off); });
    expect(screen.getByRole("checkbox")).toBeChecked();
    expect(screen.getByText(/Last confirmed setting: On/)).toBeVisible();
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("status checks stop after a bounded number of pending responses and offer reload", async () => {
  vi.useFakeTimers();
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue({ ...off, collection_status: "applying" }), updateDiagnosticsSettings: vi.fn() };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    await act(async () => { await vi.advanceTimersByTimeAsync(30000); });
    expect(api.diagnosticsSettings).toHaveBeenCalledTimes(11);
    expect(screen.getByRole("button", { name: "Reload diagnostics settings" })).toBeVisible();
    expect(screen.getByRole("alert")).toHaveTextContent("Could not confirm collection status");
    expect(screen.getByRole("checkbox")).not.toBeChecked();
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("a stalled status check times out once and ignores its late result", async () => {
  vi.useFakeTimers();
  let finish!: (value: typeof off) => void;
  const api = { diagnosticsSettings: vi.fn().mockResolvedValueOnce({ ...off, collection_status: "applying" }).mockImplementation(() => new Promise(resolve => { finish = resolve; })), updateDiagnosticsSettings: vi.fn() };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    await act(async () => { await vi.advanceTimersByTimeAsync(11000); });
    expect(screen.getByRole("alert")).toHaveTextContent("Could not confirm collection status");
    await act(async () => { finish({ enabled: true, revision: 1 }); });
    expect(screen.getByRole("checkbox")).not.toBeChecked();
    await act(async () => { await vi.advanceTimersByTimeAsync(30000); });
    expect(api.diagnosticsSettings).toHaveBeenCalledTimes(2);
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("newer pending revisions do not reset the automatic check budget", async () => {
  vi.useFakeTimers();
  let revision = 0;
  const api = { diagnosticsSettings: vi.fn(async () => ({ enabled: false, revision: revision++, collection_status: "applying" as const })), updateDiagnosticsSettings: vi.fn() };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    for (let tick = 0; tick < 15; tick++) await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    expect(api.diagnosticsSettings).toHaveBeenCalledTimes(11);
    expect(screen.getByRole("alert")).toHaveTextContent("Could not confirm collection status");
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("an uncertain save invalidates the previously applied collection status", async () => {
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue({ enabled: true, revision: 1, collection_status: "applied" }), updateDiagnosticsSettings: vi.fn().mockRejectedValue(new Error("Lost response")) };
  render(<DiagnosticsSettingsControl api={api} />);
  fireEvent.click(await screen.findByRole("checkbox"));
  await screen.findByRole("alert");
  expect(screen.getByRole("checkbox")).toBeChecked();
  expect(screen.getByText(/Collection status unavailable/)).toBeVisible();
  expect(screen.queryByText(/Setting applied/)).not.toBeInTheDocument();
});


test("the Storybook fixture confirms only on a subsequent status read", async () => {
  vi.useFakeTimers();
  const view = render(<DiagnosticsSettingsFixture />);
  try {
    await act(async () => {});
    fireEvent.click(screen.getByRole("checkbox"));
    await act(async () => {});
    expect(screen.getByText(/Applying setting/)).toBeVisible();
    await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    expect(screen.getByText(/Setting applied/)).toBeVisible();
  } finally { view.unmount(); vi.useRealTimers(); }
});
