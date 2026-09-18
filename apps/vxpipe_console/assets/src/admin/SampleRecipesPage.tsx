import { ArrowLeft, Check, SlidersHorizontal } from "lucide-react";
import { Button } from "./Button";
import { SampleRecipeCard } from "./SampleRecipeCard";
import {
  sampleRecipes,
  recipeCapabilities,
  type SampleRecipe,
} from "./sampleRecipes";
import {
  capabilityLabels,
  missingCapabilities,
  providersFor,
  setupProviders,
  type SetupProvider,
  voiceCapabilities,
  type SetupConnection,
  type SetupProviderId,
} from "./setupCatalog";

export function SampleRecipesPage({
  connections,
  providers = setupProviders,
  modelProvider,
  onModelProvider,
  onServices,
  onApiKeys,
  tenantName,
  onTry,
  installed = [],
  preparing,
  error,
}: {
  connections: SetupConnection[];
  providers?: SetupProvider[];
  modelProvider: SetupProviderId;
  onModelProvider: (provider: SetupProviderId) => void;
  onServices: () => void;
  onApiKeys: () => void;
  tenantName: string;
  onTry: (recipe: SampleRecipe) => void;
  installed?: SampleRecipe["id"][];
  preparing?: SampleRecipe["id"];
  error?: string;
}) {
  const missing = missingCapabilities(connections, providers);
  const languageProviders = providersFor("llm", connections, providers);
  const selectedModel =
    languageProviders.find((provider) => provider.id === modelProvider) ??
    languageProviders[0];
  const readyRecipes = sampleRecipes.filter((recipe) =>
    recipeCapabilities(recipe, connections, providers),
  );
  const stackCapabilities =
    missing.length && providersFor("s2s", connections, providers).length
      ? ["s2s" as const]
      : voiceCapabilities;
  const blockedMessage =
    missing.length === 1 && missing[0] === "llm"
      ? "Connect an LLM provider to try these samples."
      : `Connect ${missing.map((capability) => capabilityLabels[capability]).join(", ")} to try these samples.`;
  return (
    <>
      <Button className="setup-back" onClick={onApiKeys} variant="ghost">
        <ArrowLeft aria-hidden="true" size={15} />
        Back to API keys
      </Button>
      <header className="setup-page-heading">
        <h1>Setup Call Specs</h1>
        <p>
          Define the conversations your agents can have for {tenantName}. Start
          with a sample call spec you can customize.
        </p>
      </header>
      <div className="setup-recipe-heading">
        <h2>Load sample call specs</h2>
        <p>
          Choose a recipe to add to this tenant, then try it in the debug
          console.
        </p>
      </div>
      {readyRecipes.length === 0 ? (
        <div className="recipe-blocked">
          <div>
            <h2>A little setup, then you’re ready.</h2>
            <p>{blockedMessage}</p>
          </div>
          <Button onClick={onServices}>Set up services</Button>
        </div>
      ) : null}
      <section
        aria-label="Services used by these samples"
        className="recipe-service-strip"
      >
        <div className="recipe-stack-title">
          <SlidersHorizontal aria-hidden="true" size={17} />
          <h2>Your sample services</h2>
          <p>Chosen from this tenant’s connections.</p>
        </div>
        <div className="recipe-stack">
          {stackCapabilities.map((capability) => {
            const provider =
              capability === "llm"
                ? selectedModel
                : providersFor(capability, connections, providers)[0];
            return (
              <div className="recipe-stack-item" key={capability}>
                <span>{capabilityLabels[capability]}</span>
                {capability === "llm" && languageProviders.length > 1 ? (
                  <select
                    aria-label="Language model provider"
                    onChange={(event) =>
                      onModelProvider(event.target.value as SetupProviderId)
                    }
                    value={provider?.id}
                  >
                    {languageProviders.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.name}
                      </option>
                    ))}
                  </select>
                ) : (
                  <strong>{provider?.name ?? "Not connected"}</strong>
                )}
                {provider ? (
                  <code>{provider.defaultModels[capability]}</code>
                ) : (
                  <span className="setup-error">Setup required</span>
                )}
              </div>
            );
          })}
        </div>
      </section>
      {error ? (
        <p className="recipe-error" role="alert">
          {error} Choose the sample again to retry.
        </p>
      ) : null}
      <div className="sample-recipe-grid">
        {sampleRecipes.map((recipe) => (
          <SampleRecipeCard
            installed={installed.includes(recipe.id)}
            key={recipe.id}
            onTry={() => onTry(recipe)}
            preparing={preparing === recipe.id}
            ready={!!recipeCapabilities(recipe, connections, providers)}
            requirement={recipe.requirements
              .map((group) =>
                group
                  .map((capability) => capabilityLabels[capability])
                  .join(" + "),
              )
              .join(" or ")}
            recipe={recipe}
          />
        ))}
      </div>
      <p className="recipe-footnote">
        <Check aria-hidden="true" size={15} />
        Existing call specs are reused. Your edits are never overwritten.
      </p>
    </>
  );
}
