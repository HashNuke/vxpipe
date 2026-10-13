import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { UsersPage } from "./UsersPage";
import { roles, users } from "./fixtures";

test("uses the server-filtered result and count instead of filtering a partial page again", () => {
  render(
    <UsersPage
      users={[users[4]]}
      roles={roles}
      actorRole={roles[0]}
      query={new URLSearchParams({ q: "server-matched", page: "2" })}
      pagination={{ page: 2, page_size: 6, total: 7, total_pages: 2 }}
      onQuery={() => undefined}
      onNavigate={() => undefined}
    />,
  );

  expect(screen.getByRole("link", { name: users[4].email })).toBeVisible();
  expect(screen.getByText("7–7 of 7 users")).toBeVisible();
  const table = screen.getByRole("table", { name: "Users" });
  expect(table.tagName).toBe("TABLE");
  expect(screen.getByRole("columnheader", { name: "Tenant access" })).toBeVisible();
});
