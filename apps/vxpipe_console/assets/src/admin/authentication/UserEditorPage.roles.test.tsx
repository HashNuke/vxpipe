import {cleanup, fireEvent, render, screen, waitFor} from "@testing-library/react";
import {afterEach, expect, test, vi} from "vitest";
import {UserEditorPage} from "./UserEditorPage";
import {roles, users, tenants} from "./fixtures";
import type {Role} from "./types";
afterEach(cleanup);

test("user editor reads only its selected role and preserves memberships while role details fail", async () => {
  const source = roles.find(role => role.grants.some(grant => grant.scope === "assigned_tenants"))!;
  const target = {...users[0], roleId:source.id, memberships:[{tenantId:tenants[0].id, access:"read" as const}]};
  const options = roles.map(role=>({...role,grants:[],revision:undefined}));
  const loadRole = vi.fn<(id:string)=>Promise<Role|null>>().mockRejectedValueOnce(new Error("unavailable")).mockResolvedValue(source);
  const onSave = vi.fn().mockResolvedValue({});
  render(<UserEditorPage actorRole={roles[0]} roles={options} tenants={tenants} user={target} loadRole={loadRole} onSave={onSave} onNavigate={vi.fn()}/>);
  expect(await screen.findByRole("alert")).toHaveTextContent("role");
  expect(loadRole).toHaveBeenCalledExactlyOnceWith(source.id);
  expect(screen.queryByRole("button",{name:"Save changes"})).toBeDisabled();
  fireEvent.click(screen.getByRole("button",{name:"Retry role details"}));
  await waitFor(()=>expect(screen.getByRole("button",{name:"Save changes"})).toBeEnabled());
  fireEvent.click(screen.getByRole("button",{name:"Save changes"}));
  await waitFor(()=>expect(onSave).toHaveBeenCalled());
  expect(onSave.mock.calls[0][0].memberships).toEqual(target.memberships);
});

test("denied full-role metadata never clears a user's existing memberships", async () => {
  const source = roles.find(role => role.grants.some(grant => grant.scope === "assigned_tenants"))!;
  const target = {...users[0],roleId:source.id,memberships:[{tenantId:tenants[0].id,access:"read" as const}]};
  const loadRole = vi.fn().mockResolvedValue(null);
  const onSave = vi.fn().mockResolvedValue({});
  render(<UserEditorPage actorRole={roles[0]} roles={roles.map(role=>({...role,grants:[],revision:undefined}))} tenants={tenants} user={target} loadRole={loadRole} onSave={onSave} onNavigate={vi.fn()}/>);
  await waitFor(()=>expect(screen.getByRole("button",{name:"Save changes"})).toBeEnabled());
  fireEvent.click(screen.getByRole("button",{name:"Save changes"}));
  await waitFor(()=>expect(onSave).toHaveBeenCalled());
  expect(onSave.mock.calls[0][0].memberships).toEqual(target.memberships);
  expect(loadRole).toHaveBeenCalledExactlyOnceWith(source.id);
});
