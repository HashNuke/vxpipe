import type { Meta, StoryObj } from "@storybook/react-vite";
import { ThemeCheck } from "./ThemeCheck";
import "../admin.css";
const meta = {
  title: "Vxpipe/Console/Call spec editor/Theme check",
  component: ThemeCheck,
  parameters: { layout: "fullscreen" },
  args: { theme: "dark" },
  argTypes: { theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof ThemeCheck>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
