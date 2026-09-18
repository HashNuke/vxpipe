import { Pencil } from "lucide-react";

import type { ServiceInventoryItem } from "./serviceTypes";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";
import { ServiceLogo } from "./ServiceLogo";

export function ServiceInventory({
  onEdit,
  services,
}: {
  onEdit?: (service: ServiceInventoryItem) => void;
  services: ServiceInventoryItem[];
}) {
  return (
    <div aria-label="Services" className="overflow-x-auto">
      <div className="min-w-[680px]">
        <div aria-hidden="true" className="grid grid-cols-[minmax(190px,1.2fr)_minmax(180px,1fr)_150px_36px] gap-4 px-4 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)]">
          <span>Service</span><span>Credentials</span><span>Added / Updated</span><span />
        </div>
        <ul className="m-0 list-none p-0">
          {services.map((service) => (
            <li className="grid grid-cols-[minmax(190px,1.2fr)_minmax(180px,1fr)_150px_36px] items-center gap-4 border-t border-[var(--admin-line)] px-4 py-4" key={service.id}>
              <div className="flex min-w-0 items-center gap-3">
                <ServiceLogo name={service.name} provider={service.provider} />
                <strong className="min-w-0 truncate text-sm">{service.name}</strong>
              </div>
              <div className="min-w-0 text-sm">
                {service.credentialPreview?.map((preview) => (
                  <div className="grid min-w-0 grid-cols-[max-content_minmax(0,1fr)] items-baseline gap-x-2" key={preview.label}>
                    <span className="shrink-0 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.04em] text-[var(--admin-muted)]">{preview.label}:</span>
                    <code className="truncate text-[var(--admin-ink)]" title={`${preview.label}: ${preview.format === "last_four" ? `****${preview.lastFour}` : "******"}`}>{preview.format === "last_four" ? `****${preview.lastFour}` : "******"}</code>
                  </div>
                ))}
              </div>
              <time className="text-sm text-[var(--admin-muted)]" dateTime={service.updatedAt} title={`${new Date(service.updatedAt).toISOString()} UTC`}>
                {formatAdminRelativeTime(service.updatedAt)}
              </time>
              <button aria-label={`Edit ${service.name} credentials`} className="inline-flex size-9 items-center justify-center rounded-sm text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)]" onClick={() => onEdit?.(service)} type="button">
                <Pencil aria-hidden="true" className="size-4" />
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
