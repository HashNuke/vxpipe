import { ArrowUpRight } from "lucide-react";
import { CallStateBadge } from "../CallStateBadge";
import { formatAdminTimestamp } from "../formatAdminTimestamp";
import type { CallDirectoryItem } from "../callTypes";
export function RecentCalls({ calls, callHref }: { calls: CallDirectoryItem[]; callHref: (id: string) => string }) {
  return <ul className="navigation-recent-calls" aria-label="Recent calls">
    {calls.map(call => <li key={call.id}><a href={callHref(call.id)} target="_blank" rel="noreferrer" aria-label={`Open call ${call.id} (opens in a new tab)`}>
      <span className="navigation-recent-identity"><strong>{call.callSpecName ?? call.callSpecId}</strong><code title={call.id}>{call.id}</code></span>
      <span className="navigation-recent-state"><CallStateBadge state={call.state} /></span>
      <time dateTime={call.createdAt}>{formatAdminTimestamp(call.createdAt)}</time><ArrowUpRight className="navigation-recent-arrow" size={16} aria-hidden />
    </a></li>)}
  </ul>;
}
