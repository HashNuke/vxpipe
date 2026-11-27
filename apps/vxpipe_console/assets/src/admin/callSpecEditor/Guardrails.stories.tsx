import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import editorStory from "./flow_editor.stories";
import { GuardrailStoryPanels } from "./guardrail-story-panels";

const meta = {
  title: "Vxpipe/Console/Call spec editor/Page/Guardrails",
  component: editorStory.component,
  decorators: [Story => <GuardrailStoryPanels><Story /></GuardrailStoryPanels>],
  args: { theme: "dark", scenario: "default", transferExample: true },
  parameters: { layout: "fullscreen" },
} satisfies Meta<typeof editorStory.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const EveryTurn: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Guardrails" }));
  const panel = within(page.getByRole("tabpanel", { name: "Guardrails" }));
  await expect(panel.queryByRole("tablist")).toBeNull();
  await expect(panel.queryByRole("switch")).toBeNull();
  const before = within(panel.getByRole("region", { name: "Before turn" }));
  await expect(panel.queryByText("When blocked")).toBeNull();
  await expect(before.queryByText("Before the transcript reaches the LLM.")).toBeNull();
  const hint = before.getByRole("button", { name: "About Before turn" });
  await userEvent.click(hint);
  await expect(await page.findByText("Before the transcript reaches the LLM.")).toBeVisible();
  await userEvent.keyboard("{Escape}");
  await userEvent.click(before.getByRole("button", { name: /^Delete question:/ }));
  const after = within(panel.getByRole("region", { name: "After turn" }));
  await expect(after.getByRole("button", { name: /^Edit question:/ })).toBeVisible();
  await expect(before.queryByRole("button", { name: /^Edit question/ })).toBeNull();
  await userEvent.click(before.getByRole("button", { name: "Add question" }));
  const dialog = within(await page.findByRole("dialog", { name: "Add question" }));
  await userEvent.type(dialog.getByRole("textbox", { name: "Question" }), "Is the caller asking for another patient’s appointment details?");
  await userEvent.click(dialog.getByRole("button", { name: "Save question" }));
  await expect(before.getByRole("button", { name: /^Edit question/ })).toBeVisible();
  for (const name of ["Before turn", "After turn", "Before outgoing transfer"]) {
    await expect(page.getByRole("region", { name })).toBeVisible();
  }
} };

export const BeforeTransfer: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Guardrails" }));
  page.getByRole("region", { name: "Before outgoing transfer" }).scrollIntoView({ block: "start" });
  await expect(within(page.getByRole("region", { name: "Before outgoing transfer" })).getAllByRole("button", { name: "Add question" })).toHaveLength(1);
} };

export const TransferTool: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Tools" }));
  await expect(page.getByRole("button", { name: "Edit transfer" })).toBeVisible();
} };

export const SpeechToSpeech: Story = { args: { guardrailMode: "speech_to_speech" }, play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Guardrails" }));
  await expect(within(page.getByRole("region", { name: "Before turn" })).queryByRole("button", { name: "Add question" })).toBeNull();
  await expect(within(page.getByRole("region", { name: "After turn" })).queryByRole("button", { name: "Add question" })).toBeNull();
  await expect(within(page.getByRole("region", { name: "Before outgoing transfer" })).getByRole("button", { name: "Add question" })).toBeEnabled();
} };

export const CallDecisions: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByRole("button", { name: "Call settings" }));
  await userEvent.click(await page.findByRole("tab", { name: "Models" }));
  const decisions = await page.findByRole("combobox", { name: "Decisions" });
  await expect(decisions).toBeEnabled();
  decisions.scrollIntoView({ block: "center" });
} };

export const AgentDecisions: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Models" }));
  const decisions = await page.findByRole("combobox", { name: "Decisions" });
  await expect(decisions).toBeDisabled();
  await expect(decisions).toHaveAccessibleDescription("Change the Decisions model in Call settings → Models.");
  decisions.scrollIntoView({ block: "center" });
} };

export const EditQuestion: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("intake", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Guardrails" }));
  const before = within(page.getByRole("region", { name: "Before turn" }));
  await userEvent.click(before.getByRole("button", { name: /^Edit question/ }));
  const dialog = within(await page.findByRole("dialog", { name: "Edit question" }));
  await expect(dialog.getByRole("textbox", { name: "Question" })).toBeVisible();
  await expect(dialog.getByLabelText("Confidence threshold")).toHaveAttribute("placeholder", "0.70");
} };

export const SchedulingTransfer: Story = { play: async ({ canvasElement }) => {
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByText("scheduling", { exact: true, selector: "[data-flow-node-title-row] div" }));
  await userEvent.click(await page.findByRole("tab", { name: "Guardrails" }));
  const transfer = within(page.getByRole("region", { name: "Before outgoing transfer" }));
  await expect(transfer.queryByText("Is the caller’s consent to this transfer missing?")).toBeNull();
  await expect(transfer.getByText("Is the appointment reference missing?")).toBeVisible();
} };
