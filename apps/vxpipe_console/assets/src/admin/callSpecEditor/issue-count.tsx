import { Badge } from "../components/ui/badge";
export function IssueCount({ count = 0 }: { count?: number }) {
  return count > 0 ? <Badge aria-hidden="true" variant="destructive" className="ml-1 px-1.5 py-0 text-[10px]">{count}</Badge> : null;
}
