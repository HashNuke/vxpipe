import { Pencil } from "lucide-react";

import type { ServiceInventoryItem } from "./serviceTypes";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";
import { formatAdminLocalTimestamp } from "./formatAdminTimestamp";
import { ServiceLogo } from "./ServiceLogo";
import { capabilityLabels, setupProviders } from "./setupCatalog";

export function ServiceInventory({
  onEdit,
  services,
}: {
  onEdit?: (service: ServiceInventoryItem) => void;
  services: ServiceInventoryItem[];
}) {
  return (
    <div aria-label="Services">
      <div>
        <div
          aria-hidden="true"
          className="hidden grid-cols-[minmax(190px,1.2fr)_minmax(180px,1fr)_150px_36px] gap-4 border-b border-[var(--admin-line)] px-4 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)] sm:grid"
        >
          <span>Service</span>
          <span>Credentials</span>
          <span>Added / Updated</span>
          <span />
        </div>
        <ul className="m-0 list-none divide-y divide-[var(--admin-row-line)] p-0">
          {services.map((service) => (
            <li
              className="grid grid-cols-[minmax(0,1fr)_36px] items-start gap-x-3 gap-y-2 border-b border-[var(--admin-row-line)] px-4 py-4 sm:grid-cols-[minmax(190px,1.2fr)_minmax(180px,1fr)_150px_36px] sm:items-center sm:gap-4 sm:border-b-0"
              key={service.id}
            >
              <div className="flex min-w-0 items-start gap-3">
                <ServiceLogo name={service.name} provider={service.provider} />
                <div className="min-w-0">
                  <strong className="block min-w-0 truncate text-sm">{service.name}</strong>
                  <div className="mt-1 flex min-w-0 flex-wrap gap-1">
                    {setupProviders.find((provider) => provider.id === service.provider)?.capabilities.map((capability) => (
                      <span className="rounded-sm border border-[var(--admin-line)] px-1.5 py-0.5 text-xs text-[var(--admin-muted)]" key={capability}>
                        {capabilityLabels[capability]}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
              <div className="col-start-1 min-w-0 text-sm sm:col-auto">
                {service.credentialPreview?.map((preview) => (
                  <div
                    className="grid min-w-0 grid-cols-[max-content_minmax(0,1fr)] items-baseline gap-x-2 font-mono text-xs text-[var(--admin-muted)]"
                    key={preview.label}
                  >
                    <span className="shrink-0 font-semibold uppercase tracking-[0.04em]">
                      {preview.label}:
                    </span>
                    <code
                      className="truncate text-inherit"
                      title={`${preview.label}: ${preview.format === "last_four" ? `****${preview.lastFour}` : "******"}`}
                    >
                      {preview.format === "last_four"
                        ? `****${preview.lastFour}`
                        : "******"}
                    </code>
                  </div>
                ))}
              </div>
              <time
                className="col-start-1 text-xs text-[var(--admin-muted)] sm:col-auto sm:text-sm"
                dateTime={service.updatedAt}
                title={formatAdminLocalTimestamp(service.updatedAt)}
              >
                {formatAdminRelativeTime(service.updatedAt)}
              </time>
              <button
                aria-label={`Edit ${service.name} credentials`}
                className="col-start-2 row-start-1 inline-flex size-9 items-center justify-center rounded-sm text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)] sm:col-auto sm:row-auto"
                onClick={() => onEdit?.(service)}
                type="button"
              >
                <Pencil aria-hidden="true" className="size-4" />
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
