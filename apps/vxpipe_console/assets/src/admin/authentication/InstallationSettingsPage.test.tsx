import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { InstallationSettingsPage } from "./InstallationSettingsPage";

afterEach(cleanup);

test("changing the URL requires confirmation and preserves the draft after a failed save", async () => {
  const save = vi.fn().mockResolvedValueOnce({ error: "Could not save. Try again." }).mockResolvedValue({});
  render(<InstallationSettingsPage roleKind="superadmin" publicUrl="https://old.example.test" onSave={save} />);
  expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  fireEvent.change(screen.getByLabelText("Vxpipe URL"), { target: { value: "https://new.example.test/admin/setup" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  let dialog = screen.getByRole("dialog", { name: "Change Vxpipe URL?" });
  expect(within(dialog).getByText("https://old.example.test")).toBeVisible();
  expect(within(dialog).getByText("https://new.example.test")).toBeVisible();
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Vxpipe URL")).toHaveValue("https://new.example.test/admin/setup");
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  dialog = screen.getByRole("dialog");
  fireEvent.click(within(dialog).getByRole("button", { name: "Change URL" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not save"));
  expect(screen.getByLabelText("Vxpipe URL")).toHaveValue("https://new.example.test/admin/setup");
  fireEvent.click(within(dialog).getByRole("button", { name: "Change URL" }));
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  expect(save).toHaveBeenLastCalledWith("https://new.example.test");
  expect(screen.getByRole("status")).toHaveTextContent("Vxpipe URL updated");
});

test.each(["admin", null] as const)("%s cannot access installation settings", roleKind => {
  render(<InstallationSettingsPage roleKind={roleKind} publicUrl="https://calls.example.test" onSave={vi.fn()} />);
  expect(screen.getByRole("heading", { name: "Access unavailable" })).toBeVisible();
  expect(screen.queryByLabelText("Vxpipe URL")).not.toBeInTheDocument();
});

test("invalid edits and a normalized unchanged URL never trigger a save", () => {
  const save = vi.fn();
  render(<InstallationSettingsPage roleKind="superadmin" publicUrl="https://calls.example.test" onSave={save} />);
  fireEvent.change(screen.getByLabelText("Vxpipe URL"), { target: { value: "http://calls.example.test" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  expect(screen.getByRole("alert")).toHaveTextContent("HTTPS");
  fireEvent.change(screen.getByLabelText("Vxpipe URL"), { target: { value: "https://calls.example.test/" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(save).not.toHaveBeenCalled();
});
