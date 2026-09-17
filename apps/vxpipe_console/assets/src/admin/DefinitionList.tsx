import { DefinitionRow } from "./DefinitionRow";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";

export function DefinitionList({
  definitions,
  tenant,
  onSelectDefinition,
}: {
  definitions: DefinitionSummary[];
  tenant: TenantContext;
  onSelectDefinition?: (definitionId: string) => void;
}) {
  return (
    <div aria-label="Call definitions">
      <div
        aria-hidden="true"
        className="grid grid-cols-[minmax(0,1fr)_auto_auto_auto] gap-3 px-3 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)] sm:px-4 lg:grid-cols-[minmax(180px,1.2fr)_minmax(160px,1fr)_90px_130px_130px_auto] lg:gap-4"
      >
        <span>Definition</span>
        <span className="hidden lg:block">ID</span>
        <span>Revision</span>
        <span>State</span>
        <span className="hidden lg:block">Updated</span>
        <span className="sr-only">Open</span>
      </div>
      <ul className="m-0 list-none p-0">
        {definitions.map((definition) => (
          <DefinitionRow
            definition={definition}
            key={definition.id}
            onSelect={onSelectDefinition}
            tenant={tenant}
          />
        ))}
      </ul>
    </div>
  );
}
