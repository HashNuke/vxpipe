import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { FlowLevelInspector, type CallSettingsTab } from "./flow-level-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { validateSource } from "./validation";
import type { SourceDocument } from "./types";
import "../admin.css";

const variables: SourceDocument = { ...editorFixture, source: { ...editorFixture.source,
  call_variables: { sections: { contact: { schema: { type: "object", additionalProperties: false, required: ["phone"], properties: {
    phone: { type: "string", minLength: 3 },
    preferences: { type: "array", items: { type: "object", additionalProperties: false, properties: { channel: { type: "string", enum: ["phone", "email"] }, enabled: { type: "boolean" } } } },
  } } } } },
  participants: { ...editorFixture.source.participants, intake: { type: "agent", prompt: "Collect the caller's contact details.", variable_permissions: { contact: ["read"] } },
    reviewer: { type: "agent", prompt: "Review the caller's request.", variable_permissions: { contact: ["read"] } },
  },
} };
type Props = { theme: "dark" | "light"; initial?: SourceDocument; initialTab?: CallSettingsTab };
function CallSettingsStory({ theme, initial = editorFixture, initialTab = "direction" }: Props) {
  const [document, onChange] = useState(initial);
  const [tab, onTabChange] = useState(initialTab);
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    <FlowLevelInspector document={document} onChange={onChange} issues={validateSource(document.source)} catalog={modelCatalogFixture} tab={tab} onTabChange={onTabChange}
      lookups={{ telephonyServices: [{ key: "phone", name: "Reception phone" }], credentialNames: { deepgram: ["production"] }, mcpIntegrations: [] }} />
  </div></main></EditorTheme>;
}
const meta = { title: "Vxpipe/Console/Call spec editor/Call settings inspector", component: CallSettingsStory, parameters: { layout: "fullscreen" }, args: { theme: "dark" }, argTypes: { theme: { control: "select", options: ["dark", "light"] } } } satisfies Meta<typeof CallSettingsStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const Variables: Story = { args: { initialTab: "variables" }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Add section" }));
  await expect(canvas.getByRole("textbox", { name: "Section section_1 name" })).toHaveValue("section_1");
} };
export const NestedVariables: Story = { args: { initial: variables, initialTab: "variables" } };
export const ReadOnlyVariables: Story = { args: { initial: { ...variables, readOnly: true, source: { ...variables.source, schema_version: "20260915.01" } }, initialTab: "variables" } };
export const Defaults: Story = { args: { initialTab: "defaults" } };
export const Media: Story = { args: { initialTab: "media" } };
export const WaitSounds: Story = { args: { initialTab: "wait" } };
export const Advanced: Story = { args: { initialTab: "advanced", initial: { ...editorFixture, source: { ...editorFixture.source, transfer_policy: { attempt_timeout_ms: 900 } } } } };
