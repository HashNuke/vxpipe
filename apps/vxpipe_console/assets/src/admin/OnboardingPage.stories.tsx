import type { Meta, StoryObj } from "@storybook/react-vite";

import { OnboardingStory } from "./OnboardingStory";

const meta = {
  title: "vxpipe_console/Onboarding",
  component: OnboardingStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Three-step tenant setup prototype: Setup services, Create API Keys, then Setup Call Specs. Calls keys use calls; full tenant access uses admin and calls. Use dummy credentials: creation and validation are simulated, generated keys are nonfunctional, nothing is persisted and no provider requests are made. Recipe handoff opens the separate synthetic debug-console story; production integration is a later checkpoint.",
      },
    },
  },
  args: { scenario: "choose-services", theme: "dark" },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "creating-tenant",
        "choose-services",
        "service-picker",
        "speech-to-speech",
        "speech-to-speech-connected",
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
        "demo-nudge",
        "multiple-tenants",
        "renamed-tenant",
        "telnyx-credentials",
        "telnyx-ai-only",
        "telnyx-connected",
        "new-tenant",
        "creating-new-tenant",
        "tenant-creation-error",
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
    <OnboardingStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof OnboardingStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const ChooseServices: Story = {};
export const CreatingTenant: Story = { args: { scenario: "creating-tenant" } };
export const EnterCredentials: Story = {
  args: { scenario: "enter-credentials" },
};
export const Validating: Story = { args: { scenario: "validating" } };
export const ValidationError: Story = {
  args: { scenario: "validation-error" },
};
export const ProviderUnavailable: Story = {
  args: { scenario: "provider-unavailable" },
};
export const SpeechConnected: Story = {
  args: { scenario: "speech-connected" },
};
export const ReadyForSamples: Story = {
  args: { scenario: "ready-for-samples" },
};
export const MultipleProviders: Story = {
  args: { scenario: "multiple-providers" },
};
export const Rime: Story = { args: { scenario: "rime" } };
export const BlockedSamples: Story = { args: { scenario: "blocked-samples" } };
export const Samples: Story = { args: { scenario: "samples" } };
export const LoadingSamples: Story = { args: { scenario: "loading-samples" } };
export const SampleError: Story = { args: { scenario: "sample-error" } };
export const Complete: Story = { args: { scenario: "complete" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const DemoNudge: Story = { args: { scenario: "demo-nudge" } };
export const MultipleTenants: Story = {
  args: { scenario: "multiple-tenants" },
};
export const RenamedTenant: Story = { args: { scenario: "renamed-tenant" } };
export const TelnyxCredentials: Story = {
  args: { scenario: "telnyx-credentials" },
};
export const NewTenant: Story = { args: { scenario: "new-tenant" } };
export const CreatingNewTenant: Story = {
  args: { scenario: "creating-new-tenant" },
};
export const TenantCreationError: Story = {
  args: { scenario: "tenant-creation-error" },
};
export const NewTenantSetup: Story = { args: { scenario: "new-tenant-setup" } };
export const CreateApiKeys: Story = { args: { scenario: "api-keys" } };
export const FullTenantAccess: Story = {
  args: { scenario: "api-key-full-access" },
};
export const CreatingApiKey: Story = { args: { scenario: "api-key-creating" } };
export const ApiKeyError: Story = { args: { scenario: "api-key-error" } };
export const ApiKeyCreated: Story = { args: { scenario: "api-key-created" } };
export const ExistingApiKey: Story = { args: { scenario: "api-key-existing" } };
export const SetupCallSpecs: Story = { args: { scenario: "samples" } };
export const Light: Story = { args: { theme: "light" } };
export const SamplesLight: Story = {
  args: { scenario: "samples", theme: "light" },
};
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};

export const ServicePicker: Story = { args: { scenario: "service-picker" } };
export const SpeechToSpeechPreview: Story = {
  args: { scenario: "speech-to-speech" },
  parameters: {
    docs: {
      description: {
        story:
          "Future-capability design preview: the Google card stands in for a speech-to-speech integration. No audio model or provider capability is added to the runtime. Only the voice-conversation recipe accepts this simulated path; handoff recipes retain their existing pipeline requirements.",
      },
    },
  },
};
export const SpeechToSpeechConnectedPreview: Story = {
  ...SpeechToSpeechPreview,
  args: { scenario: "speech-to-speech-connected" },
};

export const TelnyxAiOnly: Story = { args: { scenario: "telnyx-ai-only" } };
export const TelnyxConnected: Story = {
  args: { scenario: "telnyx-connected" },
};
