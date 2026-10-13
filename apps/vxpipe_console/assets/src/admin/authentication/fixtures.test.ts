import { expect, test } from "vitest";
import { roles, users } from "./fixtures";

test("storybook uses only the four supported starting roles", () => {
  expect(roles.map((role) => role.name)).toEqual([
    "Superadmin",
    "Admin",
    "Tenant Manager",
    "Tenant Member",
  ]);
  expect(users.every((user) => roles.some((role) => role.id === user.roleId))).toBe(true);
});
