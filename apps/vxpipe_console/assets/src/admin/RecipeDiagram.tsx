import { Bot, Headphones, User } from "lucide-react";
import type { SampleRecipe } from "./sampleRecipes";

export function RecipeDiagram({ kind }: { kind: SampleRecipe["id"] }) {
  const nodes =
    kind === "voice"
      ? [
          { x: 78, label: "You", role: "caller" },
          { x: 238, label: "Assistant", role: "agent" },
        ]
      : [
          { x: 46, label: "You", role: "caller" },
          {
            x: 158,
            label: kind === "agents" ? "Receptionist" : "Assistant",
            role: "agent",
          },
          {
            x: 270,
            label: kind === "agents" ? "Specialist" : "Support",
            role: kind === "agents" ? "agent" : "human",
          },
        ];
  return (
    <svg aria-hidden="true" className="recipe-diagram" viewBox="0 0 316 172">
      {kind === "voice" ? (
        <>
          <path className="recipe-wire" d="M108 71H208" />
          {[10, 22, 34, 18, 30, 12, 24].map((height, index) => (
            <path
              className="recipe-wave"
              d={`M${134 + index * 8} ${71 - height / 2}v${height}`}
              key={index}
            />
          ))}
        </>
      ) : (
        <>
          <path className="recipe-wire" d="M76 71H128M188 71H240" />
          <path className="recipe-arrow" d="m108 67 5 4-5 4m112-8 5 4-5 4" />
        </>
      )}
      {nodes.map((node) => {
        const Icon =
          node.role === "caller"
            ? User
            : node.role === "human"
              ? Headphones
              : Bot;
        return (
          <g
            className={`recipe-node recipe-node--${node.role}`}
            key={node.label}
          >
            <rect height="58" rx="12" width="58" x={node.x - 29} y="42" />
            <Icon height={25} width={25} x={node.x - 12.5} y={58.5} />
            <text x={node.x} y="124">
              {node.label}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
