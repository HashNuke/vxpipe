import { ArrowUpRight, Check, LockKeyhole } from "lucide-react";
import { Button } from "./Button";
import { RecipeDiagram } from "./RecipeDiagram";
import type { SampleRecipe } from "./sampleRecipes";

export function SampleRecipeCard({
  recipe,
  ready,
  requirement,
  installed,
  preparing,
  onTry,
}: {
  recipe: SampleRecipe;
  ready: boolean;
  requirement: string;
  installed?: boolean;
  preparing?: boolean;
  onTry: () => void;
}) {
  return (
    <article aria-labelledby={`recipe-${recipe.id}`} className="sample-recipe">
      <div className="recipe-art">
        <RecipeDiagram kind={recipe.id} />
        {installed ? (
          <span className="recipe-installed">
            <Check aria-hidden="true" size={13} />
            Added
          </span>
        ) : null}
      </div>
      <div className="recipe-content">
        <p className="recipe-participants">{recipe.participants}</p>
        <h2 id={`recipe-${recipe.id}`}>{recipe.title}</h2>
        <p className="recipe-description">{recipe.description}</p>
        <div className="recipe-prompt">
          <span>Try saying</span>
          <p>“{recipe.prompt}”</p>
        </div>
        <div className="recipe-bottom">
          <span>
            {recipe.id === "human"
              ? "Opens a separate support seat"
              : "Runs in your browser"}
          </span>
          {!ready ? (
            <p className="recipe-requirement">Requires {requirement}.</p>
          ) : null}
          <Button
            aria-label={`${installed ? "Open" : "Load"} ${recipe.title}`}
            className={ready ? "setup-primary" : undefined}
            disabled={!ready || preparing}
            onClick={onTry}
          >
            {preparing ? "Loading…" : installed ? "Open sample" : "Load sample"}
            {ready ? (
              <ArrowUpRight aria-hidden="true" size={15} />
            ) : (
              <LockKeyhole aria-hidden="true" size={14} />
            )}
          </Button>
        </div>
      </div>
    </article>
  );
}
