import type { Meta } from "@storybook/react-vite";

import { SetupStory } from "./SetupStory";

export const setupMeta = {
  component: SetupStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Tenant and platform setup fixtures. Credentials, validation, API keys and sample calls are simulated locally; no provider requests are made.",
      },
    },
  },
  args: {
    scenario: "choose-services",
    theme: "dark",
    publicOrigin:
      import.meta.env.STORYBOOK_APP_ORIGIN ?? "http://localhost:4000",
  },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "platform-services",
        "platform-configured",
        "platform-telnyx",
        "inherited-services",
        "tenant-override",
        "tenant-override-error",
        "creating-tenant",
        "choose-services",
        "service-picker",
        "enter-credentials",
        "validating",
        "validation-error",
        "provider-unavailable",
        "speech-connected",
        "ready-for-samples",
        "multiple-providers",
        "rime",
        "blocked-samples",
        "samples",
        "loading-samples",
        "sample-error",
        "complete",
        "unavailable",
        "renamed-tenant",
        "telnyx-credentials",
        "telnyx-ai-only",
        "telnyx-connected",
        "new-tenant-setup",
        "api-keys",
        "api-key-full-access",
        "api-key-creating",
        "api-key-error",
        "api-key-created",
        "api-key-existing",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <SetupStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof SetupStory>;
