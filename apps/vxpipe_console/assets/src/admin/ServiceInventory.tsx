import { CircleMinus, KeyRound } from "lucide-react";

import type { ServiceInventoryItem } from "./serviceTypes";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";

export function ServiceInventory({ services }: { services: ServiceInventoryItem[] }) {
  return (
    <div aria-label="Services" className="overflow-x-auto">
      <div className="min-w-[560px]">
        <div aria-hidden="true" className="grid grid-cols-[minmax(190px,1.4fr)_130px_150px] gap-4 px-4 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)]">
          <span>Service</span><span>Credential</span><span>Added / Updated</span>
        </div>
        <ul className="m-0 list-none p-0">
          {services.map((service) => (
            <li className="grid grid-cols-[minmax(190px,1.4fr)_130px_150px] items-center gap-4 border-t border-[var(--admin-line)] px-4 py-4" key={service.id}>
              <strong className="min-w-0 truncate text-sm">{service.name}</strong>
              <span className={service.credentialName ? "inline-flex min-w-0 items-center gap-1.5 text-sm text-[var(--admin-green)]" : "inline-flex min-w-0 items-center gap-1.5 text-sm text-[var(--admin-muted)]"}>
                {service.credentialName ? <KeyRound aria-hidden="true" className="size-4 shrink-0" /> : <CircleMinus aria-hidden="true" className="size-4 shrink-0" />}
                <span className="min-w-0">{service.credentialName ? <><span className="block">Credential stored</span><span className="block truncate text-xs text-[var(--admin-muted)]" title={service.credentialName}>{service.credentialName}</span></> : "Missing"}</span>
              </span>
              <time className="text-sm text-[var(--admin-muted)]" dateTime={service.updatedAt} title={`${new Date(service.updatedAt).toISOString()} UTC`}>
                {formatAdminRelativeTime(service.updatedAt)}
              </time>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
