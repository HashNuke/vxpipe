import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { MemoryRouter, useLocation } from "react-router";
import { AuthenticationApi } from "../authentication/authenticationApi";
import { roles, users } from "../authentication/fixtures";
import { ConsoleNavigation } from "./ConsoleNavigation";
import { NavigationApi } from "./navigationApi";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });
function Location() { return <output aria-label="Current route">{useLocation().pathname}</output>; }

test("a direct settings visit can return to the regular directory for an all-tenant operator", async () => {
  vi.spyOn(NavigationApi.prototype, "navigation").mockResolvedValue({ actor: { id: users[0].id, kind: "superadmin" }, scope: "all", directoryAccess: true, directoryPath: "/tenants", landingPath: "/tenants", platform: [{ label: "Roles", href: "/roles" }], tenant: null });
  vi.spyOn(AuthenticationApi.prototype, "session").mockResolvedValue({ user: users[0], role: roles[0] });
  render(<MemoryRouter initialEntries={["/roles"]}><ConsoleNavigation csrfToken="test"><Location /></ConsoleNavigation></MemoryRouter>);
  await screen.findByRole("link", { name: "Roles" });
  fireEvent.click(screen.getByRole("link", { name: "Back to tenants" }));
  await screen.findByRole("combobox", { name: "Switch tenant" });
  expect(screen.getByLabelText("Current route")).toHaveTextContent("/tenants");
  expect(screen.getByRole("link", { name: "Settings" })).toHaveAttribute("href", "/roles");
});
