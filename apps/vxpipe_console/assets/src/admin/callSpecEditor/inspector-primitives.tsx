import type { ReactNode } from "react"
import type { LucideIcon } from "lucide-react"
import { Label } from "../components/ui/label"

export function FieldLabel({ children }: { children: ReactNode }) {
  return <Label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{children}</Label>
}

export function InspectorShell({ title, subtitle, icon: Icon, children }: { title: string; subtitle?: string; icon?: LucideIcon; children: ReactNode }) {
  return (
    <aside className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-card">
      <div className="shrink-0 border-b border-border p-4">
        <div className="flex items-center gap-2 text-sm font-semibold text-foreground">
          {Icon && <Icon className="h-4 w-4 text-muted-foreground" />}
          <span>{title}</span>
        </div>
        {subtitle && <div className="mt-0.5 text-xs text-muted-foreground">{subtitle}</div>}
      </div>
      <div className="min-h-0 flex-1 overflow-auto p-4">{children}</div>
    </aside>
  )
}

export function InspectorRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3">
      <dt className="shrink-0 text-muted-foreground">{label}</dt>
      <dd className="text-right font-medium text-foreground">{value}</dd>
    </div>
  )
}
