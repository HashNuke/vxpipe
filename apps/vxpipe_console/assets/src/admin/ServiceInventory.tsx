import { Check, CircleMinus, KeyRound } from "lucide-react";

import type { ServiceInventoryItem } from "./serviceTypes";

const providerLabels = {
  google: "Google",
  zenmux: "Zenmux",
  deepgram: "Deepgram",
  telnyx: "Telnyx",
  twilio: "Twilio",
} as const;

function statusLabel(status: ServiceInventoryItem["serviceStatus"]) {
  switch (status) {
    case "not-applicable":
      return "—";
    case "not-registered":
      return "Not registered";
    case "registered":
      return "Registered";
  }
}

export function ServiceInventory({ services }: { services: ServiceInventoryItem[] }) {
  return (
    <div aria-label="Services" className="overflow-x-auto">
      <div className="min-w-[680px]">
        <div aria-hidden="true" className="grid grid-cols-[minmax(190px,1.4fr)_120px_130px_150px] gap-4 px-4 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)]">
          <span>Service</span><span>Capability</span><span>Credential</span><span>Service status</span>
        </div>
        <ul className="m-0 list-none p-0">
          {services.map((service) => (
            <li className="grid grid-cols-[minmax(190px,1.4fr)_120px_130px_150px] items-center gap-4 border-t border-[var(--admin-line)] px-4 py-4" key={service.id}>
              <span className="min-w-0"><strong className="block truncate text-sm">{service.name}</strong><span className="mt-1 block text-xs text-[var(--admin-muted)]">{providerLabels[service.provider]}</span>{service.telephonyConfiguration ? <span className="mt-1 block truncate font-mono text-xs text-[var(--admin-muted)]">{service.telephonyConfiguration.providerConnectionId}{service.telephonyConfiguration.outboundNumber ? ` · ${service.telephonyConfiguration.outboundNumber}` : ""}</span> : service.capability === "Telephony" ? <span className="mt-1 block text-xs text-[var(--admin-muted)]">No telephony service registered</span> : null}</span>
              <span className="text-sm text-[var(--admin-muted)]">{service.capability}</span>
              <span className={service.credentialName ? "inline-flex min-w-0 items-center gap-1.5 text-sm text-[var(--admin-green)]" : "inline-flex min-w-0 items-center gap-1.5 text-sm text-[var(--admin-muted)]"}>
                {service.credentialName ? <KeyRound aria-hidden="true" className="size-4 shrink-0" /> : <CircleMinus aria-hidden="true" className="size-4 shrink-0" />}
                <span className="min-w-0">{service.credentialName ? <><span className="block">Credential stored</span><span className="block truncate text-xs text-[var(--admin-muted)]" title={service.credentialName}>{service.credentialName}</span></> : "Missing"}</span>
              </span>
              <span className={service.serviceStatus === "registered" ? "inline-flex items-center gap-1.5 text-sm text-[var(--admin-green)]" : "text-sm text-[var(--admin-muted)]"}>
                {service.serviceStatus === "registered" ? <Check aria-hidden="true" className="size-4" /> : null}
                {statusLabel(service.serviceStatus)}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
