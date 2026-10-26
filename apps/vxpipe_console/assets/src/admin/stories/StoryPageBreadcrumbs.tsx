import { Building2, ChevronRight } from "lucide-react";
import { useContext } from "react";
import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import { StoryNavigationContext, type StoryCrumb } from "./storyNavigation";
import "./page-breadcrumbs.css";

export function StoryPageBreadcrumbs({ items, root, tenant, disabled = false, onNavigate }: {
  items: StoryCrumb[];
  root?: StoryCrumb;
  tenant?: boolean;
  disabled?: boolean;
  onNavigate?: (path: string) => void;
}) {
  const navigation = useContext(StoryNavigationContext);
  const first = root ?? navigation?.root;
  const crumbs = first ? [first, ...items] : items;
  const navigate = onNavigate ?? navigation?.navigate;
  return <nav aria-label="Breadcrumb" className="page-breadcrumbs"><ol>
    {crumbs.map((crumb, index) => <li key={`${index}-${crumb.label}`}>
      {index ? <ChevronRight size={14} aria-hidden /> : (tenant ?? navigation?.tenant) ? <Building2 size={15} aria-hidden /> : null}
      {index === crumbs.length - 1 ? <span aria-current="page" title={crumb.label}>{crumb.label}</span>
        : crumb.href && !disabled ? <a href={crumb.href.startsWith("/") ? `#${crumb.href}` : crumb.href} title={crumb.label} onClick={event => {
          if (!shouldInterceptNavigation(event) || (!crumb.onSelect && !navigate)) return;
          event.preventDefault();
          if (crumb.onSelect) crumb.onSelect(); else navigate?.(crumb.href!);
        }}>{crumb.label}</a>
          : crumb.onSelect ? <button type="button" disabled={disabled} onClick={crumb.onSelect} title={crumb.label}>{crumb.label}</button>
            : <span title={crumb.label}>{crumb.label}</span>}
    </li>)}
  </ol></nav>;
}
