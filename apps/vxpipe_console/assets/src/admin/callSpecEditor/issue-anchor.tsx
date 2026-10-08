import type { ReactNode } from "react";
import { useIssueField } from "./issue-context";
import type { SourceIssue } from "./types";
export function IssueAnchor({ path, issues, children, className }: { path: string[]; issues?: SourceIssue[]; children: ReactNode; className?: string }) {
  const { ref, errors } = useIssueField(path, issues, false);
  return <div ref={ref} tabIndex={-1} data-field-path={JSON.stringify(path)} className={className}>
    {children}{errors.map((issue, index) => <p key={index} className="mt-2 text-xs text-destructive">{issue.reason}</p>)}
  </div>;
}
