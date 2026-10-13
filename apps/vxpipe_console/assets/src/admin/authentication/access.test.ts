import { describe, expect, it } from "vitest";
import { canManageUser, effectiveAccess, validatePassword } from "./access";
import { roles } from "./fixtures";

describe("account authority shown in the prototype", () => {
  it("allows Admins to manage members, but not privileged accounts or promotions", () => {
    const [superadmin, admin, , , member] = roles;
    expect(canManageUser(admin, member)).toBe(true);
    expect(canManageUser(admin, admin)).toBe(false);
    expect(canManageUser(admin, superadmin)).toBe(false);
    expect(canManageUser(admin, member, admin)).toBe(false);
    expect(canManageUser(admin, admin, member)).toBe(false);
    expect(canManageUser(superadmin, admin)).toBe(true);
  });
  it("keeps reserved writes out of custom roles, even with a forged grant", () => {
    const [superadmin, admin, , , member] = roles;
    expect(
      canManageUser(
        {
          ...member,
          grants: [
            { permission: "users.superadmins.write", scope: "installation" },
          ],
        },
        superadmin,
      ),
    ).toBe(false);
    expect(canManageUser(member, admin)).toBe(false);
  });
  it("caps assigned permissions without removing independent all-tenant grants", () => {
    const member = roles[4];
    expect(effectiveAccess(member, "calls")).toBe("none");
    expect(effectiveAccess(member, "calls", "read")).toBe("read");
    expect(effectiveAccess(member, "calls", "read_write")).toBe("write");
    const mixed = {
      ...member,
      grants: [
        { permission: "calls.read", scope: "all_tenants" as const },
        { permission: "call_specs.read", scope: "assigned_tenants" as const },
      ],
    };
    expect(effectiveAccess(mixed, "calls")).toBe("read");
    expect(effectiveAccess(mixed, "call_specs", "read_write")).toBe("read");
  });
  it("validates the chosen password and confirmation without trimming it", () => {
    expect(
      validatePassword("an example passphrase", "different passphrase"),
    ).toMatch(/match/);
    expect(validatePassword("short", "short")).toMatch(/15/);
    expect(
      validatePassword(" an example passphrase ", "an example passphrase"),
    ).toMatch(/match/);
    expect(
      validatePassword("an example passphrase", "an example passphrase"),
    ).toBeUndefined();
  });
});
