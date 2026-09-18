import {
  providersFor,
  setupProviders,
  voiceCapabilities,
  type SetupConnection,
  type VoiceCapability,
} from "./setupCatalog";

export type SampleRecipe = {
  id: "voice" | "agents" | "human";
  title: string;
  description: string;
  prompt: string;
  participants: string;
  requirements: VoiceCapability[][];
};

export const sampleRecipes: SampleRecipe[] = [
  {
    id: "voice",
    requirements: [voiceCapabilities, ["s2s"]],
    title: "Voice conversation",
    description:
      "Meet your first voice agent. Speak naturally and hear it answer in real time.",
    prompt: "Tell me something interesting about the ocean.",
    participants: "You + one agent",
  },
  {
    id: "agents",
    requirements: [voiceCapabilities],
    title: "Agent handoff",
    description:
      "Start with a receptionist, then hand the conversation to a specialist with context intact.",
    prompt: "Can I speak with the specialist?",
    participants: "You + two agents",
  },
  {
    id: "human",
    requirements: [voiceCapabilities],
    title: "Human handoff",
    description:
      "Let an agent welcome the caller, then bring a person into the conversation.",
    prompt: "I’d like to talk to a person.",
    participants: "You + an agent + a support seat",
  },
];

export function recipeCapabilities(
  recipe: SampleRecipe,
  connections: SetupConnection[],
  providers = setupProviders,
) {
  return recipe.requirements.find((capabilities) =>
    capabilities.every(
      (capability) =>
        providersFor(capability, connections, providers).length > 0,
    ),
  );
}
