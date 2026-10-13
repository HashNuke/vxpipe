import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { AuthenticationJourney } from "./AuthenticationJourney";
import { AuthPage } from "./AuthPage";
import { ResetPasswordPage } from "./ResetPasswordPage";
import { roles, users } from "./fixtures";

beforeEach(() => {
  vi.spyOn(window, "scrollTo").mockImplementation(() => undefined);
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  window.history.replaceState({}, "", "/");
});
test("page navigation returns to the top while directory filters retain scroll", () => {
  render(<AuthenticationJourney actor="admin" />);
  vi.mocked(window.scrollTo).mockClear();
  fireEvent.change(screen.getByRole("combobox", { name: "Filter by role" }), {
    target: { value: roles[0].id },
  });
  expect(window.scrollTo).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("link", { name: "owner@example.test" }));
  expect(window.scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "instant" });
});

test("an upgraded installation asks for its local setup proof", async () => {
  const submit = vi.fn().mockResolvedValue({});
  render(<AuthPage mode="setup" proofRequired onSubmit={submit} />);
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "owner@example.test" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Local setup proof"), { target: { value: "local-proof" } });
  fireEvent.click(screen.getByRole("button", { name: /Create Superadmin account/ }));
  await waitFor(() => expect(submit).toHaveBeenCalledWith("owner@example.test", "an example passphrase", "local-proof"));
});

test("local recovery asks for proof and confirmed replacement password", async () => {
  const submit = vi.fn().mockResolvedValue({});
  render(<AuthPage mode="recover" onSubmit={submit} />);

  expect(screen.getByRole("heading", { name: "Recover Superadmin access" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "owner@example.test" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Local recovery proof"), { target: { value: "local-proof" } });
  fireEvent.click(screen.getByRole("button", { name: /Recover access/ }));

  await waitFor(() => expect(submit).toHaveBeenCalledWith("owner@example.test", "an example passphrase", "local-proof"));
});
test("an Admin filters for Superadmins and can only view them", () => {
  render(<AuthenticationJourney actor="admin" />);
  fireEvent.change(screen.getByRole("combobox", { name: "Filter by role" }), {
    target: { value: roles[0].id },
  });
  expect(
    screen.getByRole("link", { name: "owner@example.test" }),
  ).toBeVisible();
  expect(
    screen.queryByRole("link", { name: "member@example.test" }),
  ).not.toBeInTheDocument();
  expect(window.location.hash).toContain("role=");
  fireEvent.click(screen.getByRole("link", { name: "owner@example.test" }));
  expect(
    screen.getByText("This account is read-only for your role."),
  ).toBeVisible();
  expect(
    screen.queryByRole("button", { name: "Save changes" }),
  ).not.toBeInTheDocument();
  expect(
    screen.queryByRole("link", { name: "Reset password" }),
  ).not.toBeInTheDocument();
});
test("password reset validates confirmation before calling the supplied action", async () => {
  const reset = vi.fn().mockResolvedValue({});
  render(
    <ResetPasswordPage
      actorRole={roles[0]}
      targetRole={roles[1]}
      user={users[1]}
      onReset={reset}
      onNavigate={() => undefined}
    />,
  );
  fireEvent.change(screen.getByLabelText("New password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "a different passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Set password" }));
  expect(screen.getByRole("alert")).toHaveTextContent("Passwords do not match");
  expect(reset).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Set password" }));
  await waitFor(() => expect(reset).toHaveBeenCalledOnce());
  await waitFor(() =>
    expect(screen.getByLabelText("New password")).toHaveValue(""),
  );
});
test("a member cannot bypass account reset by loading the route directly", () => {
  render(
    <AuthenticationJourney
      actor="member"
      initialPath={`/admin/users/${users[1].id}/reset-password`}
    />,
  );
  expect(
    screen.getByRole("heading", { name: "Access unavailable" }),
  ).toBeVisible();
  expect(screen.queryByLabelText("New password")).not.toBeInTheDocument();
});
test("creates an account and assigns one tenant without changing the current actor", async () => {
  render(<AuthenticationJourney initialPath="/admin/users/new" />);
  fireEvent.change(screen.getByLabelText("Email"), {
    target: { value: "new.user@example.test" },
  });
  fireEvent.change(screen.getByLabelText("Password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.change(screen.getByLabelText("Confirm password"), {
    target: { value: "an example passphrase" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Add tenants" }));
  fireEvent.click(screen.getByRole("checkbox", { name: /Northwind/ }));
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fireEvent.click(screen.getByRole("button", { name: "Create user" }));
  await waitFor(() =>
    expect(screen.getByRole("heading", { name: "User details" })).toBeVisible(),
  );
  expect(screen.getByLabelText("Email")).toHaveValue("new.user@example.test");
  expect(screen.getByText("Northwind")).toBeVisible();
  expect(
    screen.getByRole("link", { name: "owner@example.test" }),
  ).toBeVisible();
});
