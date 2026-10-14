import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import calls from "../CallSpecCallsPage.stories";
import specs from "../TenantCallSpecsPage.stories";
import services from "../TenantServicesPage.stories";
vi.mock("@vxpipe/react", () => ({ CallConsole: () => <div>Call inspector</div> }));
vi.mock("../callSpecEditor/flow-canvas", () => ({ FlowCanvas: () => <div>Editor canvas</div> }));
beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });
test.each([["Calls", calls], ["Call Specs", specs], ["Services", services]] as const)("%s page states use the shared sidebar", (title, meta) => {
  const Story = meta.render;
  render(<Story scenario="populated" theme="dark" />);
  expect(screen.getAllByRole("complementary", { name: "Console navigation" })).toHaveLength(1);
  expect(screen.getByRole("heading", { name: title, level: 1 })).toBeVisible();
  expect(screen.queryByRole("navigation", { name: "Tenant workspace" })).not.toBeInTheDocument();
  expect(within(screen.getByRole("navigation", { name: "Tenant" })).getByRole("link", { name: title })).toHaveAttribute("aria-current", "page");
});

test("history links point to the standalone history story", async () => {
  const { callDetailsStoryHref } = await import("../adminStoryHref");
  const url = new URL(callDetailsStoryHref("tenant", "call", "dark"), "http://storybook.test");
  expect(url.searchParams.get("id")).toBe("vxpipe-console-calls-history--ongoing");
});

test("directory fixture rows open that tenant's sidebar dashboard", async () => {
  const { TenantDirectoryStory } = await import("./ResourceStories");
  render(<TenantDirectoryStory scenario="populated" theme="dark" />);
  const { fireEvent } = await import("@testing-library/react");
  fireEvent.click(screen.getByRole("link", { name: "Open Courier operations" }));
  expect(screen.getByRole("heading", { name: "Dashboard", level: 1 })).toBeVisible();
  expect(screen.getByRole("combobox", { name: "Switch tenant" })).toHaveTextContent("Courier operations");
});

test("member authority survives switching from an account story to a tenant", async () => {
  const { AuthenticationStory } = await import("./AuthenticationStory");
  const { fireEvent } = await import("@testing-library/react");
  render(<AuthenticationStory actor="member" initialPath="/account" followLocation={false} />);
  fireEvent.click(screen.getByRole("combobox", { name: "Switch tenant" }));
  fireEvent.click(await screen.findByRole("option", { name: /Acme/ }));
  expect(screen.getByRole("heading", { name: "Dashboard", level: 1 })).toBeVisible();
  expect(screen.queryByRole("navigation", { name: "Platform" })).not.toBeInTheDocument();
});

test("shared controls are isolated from page navigation", async () => {
  const { ComponentExamples } = await import("../authentication/ComponentExamples");
  render(<ComponentExamples component="passwords" />);
  expect(screen.queryByText("Vxpipe")).not.toBeInTheDocument();
  expect(screen.queryByRole("complementary")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Password", { exact: true })).toBeVisible();
});

test("call history return links retain the call spec filter", async () => {
  const { callSpecs } = await import("../callSpecFixtures");
  const { CallsPageStory } = await import("./ResourceStories");
  window.history.replaceState({}, "", `#/admin/tenants/tn_demo_01/calls?call_spec_id=${callSpecs[1].id}`);
  render(<CallsPageStory scenario="populated" theme="dark" />);
  expect(screen.getByRole("combobox", { name: "Call spec" })).toHaveTextContent("Appointment reminders");
});

test.each(["api-key-existing", "choose-services"] as const)("%s identifies the tenant above its content", async scenario => {
  const { SetupStory } = await import("./SetupStory");
  render(<SetupStory scenario={scenario} theme="dark" />);
  expect(within(screen.getByRole("main")).getByText("Demo", { exact: true })).toBeVisible();
});
