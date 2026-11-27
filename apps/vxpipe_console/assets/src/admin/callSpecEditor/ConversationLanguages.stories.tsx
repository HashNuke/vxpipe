import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, within, userEvent } from "storybook/test";
import editorStory from "./flow_editor.stories";

function Preview({ initial }: {initial: string[]}) {
  const EditorPage = editorStory.component;
  return <EditorPage theme="dark" scenario="default" conversationLanguages={initial} />;
}

const meta = {
  title: "Vxpipe/Console/Call spec editor/Page/Conversation languages",
  component: Preview,
  parameters: {layout: "fullscreen"},
  args: {initial: ["en", "es", "fr"]},
  play: async ({canvasElement}) => {
    const page = within(canvasElement.ownerDocument.body);
    await userEvent.click(await page.findByRole("button", {name: "Call settings"}));
    await userEvent.click(await page.findByRole("tab", {name: "Models"}));
    await expect(page.findByRole("combobox", {name: "Conversation languages"})).resolves.toBeVisible();
  },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const PriorityOrder: Story = {};
export const Automatic: Story = {args: {initial: []}};
export const AmbiguousCodes: Story = {
  args: {initial: ["tl", "fil", "cmn-CN", "zh-CN"]},
  play: async ({canvasElement}) => {
    const page = within(canvasElement.ownerDocument.body);
    await userEvent.click(await page.findByRole("button", {name: "Call settings"}));
    await userEvent.click(await page.findByRole("tab", {name: "Models"}));
    await expect(page.findByRole("combobox", {name: "Conversation languages"})).resolves.toBeVisible();
    await expect(page.findByText("Tagalog")).resolves.toBeVisible();
    await expect(page.findByText("Filipino")).resolves.toBeVisible();
    await expect(page.findByText("Mandarin (China)")).resolves.toBeVisible();
    await expect(page.findByText("Chinese (China)")).resolves.toBeVisible();
    for (const code of ["tl", "fil", "cmn-CN", "zh-CN"]) {
      await expect(page.findByText(code, {selector: "span.text-muted-foreground"})).resolves.toBeVisible();
    }
  },
};
