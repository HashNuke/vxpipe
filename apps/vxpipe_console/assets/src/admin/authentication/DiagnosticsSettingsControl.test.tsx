import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { DiagnosticsSettingsFixture } from "./DiagnosticsSettingsFixture";
import { DiagnosticsSettingsControl } from "./DiagnosticsSettingsControl";
import { AuthenticationError } from "./authenticationApi";

afterEach(cleanup);
const off = { enabled: false, revision: 0 };
const label = "Benchmark using Silero VAD";

test("keeps the saved value until persistence succeeds", async () => {
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
  expect(screen.queryByText(/Collection status unavailable/)).not.toBeInTheDocument();
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


test("the conflict story reloads the other operator's saved revision before retrying", async () => {
  render(<DiagnosticsSettingsFixture scenario="conflict" />);
  fireEvent.click(await screen.findByRole("checkbox"));
  expect(await screen.findByRole("alert")).toHaveTextContent("changed elsewhere");
  expect(screen.getByRole("checkbox")).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Reload diagnostics settings" }));
  await waitFor(() => expect(screen.getByRole("checkbox")).toBeEnabled());
  expect(screen.getByRole("checkbox")).toBeChecked();
  fireEvent.click(screen.getByRole("checkbox"));
  await waitFor(() => expect(screen.getByRole("checkbox")).not.toBeChecked());
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});

test("saved settings need no propagation status or background polling", async () => {
  vi.useFakeTimers();
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue(off), updateDiagnosticsSettings: vi.fn().mockResolvedValue({ enabled: true, revision: 1 }) };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    expect(screen.queryByText(/Applying setting|Setting applied|Collection status/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("checkbox", { name: label }));
    await act(async () => {});
    await act(async () => { await vi.advanceTimersByTimeAsync(30000); });
    expect(screen.getByRole("checkbox")).toBeChecked();
    expect(api.diagnosticsSettings).toHaveBeenCalledOnce();
    expect(screen.queryByText(/Applies to new calls/)).not.toBeInTheDocument();
  } finally { view.unmount(); vi.useRealTimers(); }
});

test("a successful save confirms with a dismissing toast instead of inline page text", async () => {
  vi.useFakeTimers();
  const api = { diagnosticsSettings: vi.fn().mockResolvedValue(off), updateDiagnosticsSettings: vi.fn().mockResolvedValue({ enabled: true, revision: 1 }) };
  const view = render(<DiagnosticsSettingsControl api={api} />);
  try {
    await act(async () => {});
    fireEvent.click(screen.getByRole("checkbox", { name: label }));
    await act(async () => {});
    expect(screen.getByLabelText("Notification")).toHaveTextContent("Diagnostics setting saved.");
    await act(async () => { await vi.advanceTimersByTimeAsync(6000); });
    expect(screen.queryByText("Diagnostics setting saved.")).not.toBeInTheDocument();
  } finally { view.unmount(); vi.useRealTimers(); }
});
