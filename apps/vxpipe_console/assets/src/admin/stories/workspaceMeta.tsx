import type { Meta } from "@storybook/react-vite";
import { NavigationJourney } from "../navigation/NavigationJourney";
import { tenants } from "../authentication/fixtures";
const tenant = `/t/${tenants[0].key}`;
export const workspaceMeta = {
  component: NavigationJourney,
  args: { persona: "all", theme: "dark", initialPath: `${tenant}/dashboard`, state: "ready", pickerState: "ready" },
  argTypes: { persona: { control: "select", options: ["all", "single", "multiple", "member", "mixed", "none", "keys-only", "platform-reader", "service-reader"] }, theme: { control: "select", options: ["dark", "light"] }, state: { control: "select", options: ["ready", "loading", "unavailable", "empty"] }, pickerState: { control: "select", options: ["ready", "loading", "unavailable"] } },
  parameters: { docs: { description: { component: "Navigation and dashboard reference stories. Synthetic fixtures only; no backend calls. Permission profiles model the implemented authorization contract; the Console uses production routes and scoped APIs. Story links stay inside this fixture journey; specialized editors/inspectors stay standalone." } } },
  render: args => <NavigationJourney key={`${args.persona}-${args.theme}-${args.initialPath}-${args.state}-${args.pickerState}`} {...args} />,
} satisfies Meta<typeof NavigationJourney>;
