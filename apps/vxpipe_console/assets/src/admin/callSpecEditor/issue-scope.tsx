import { useCallback, useContext, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { closestField, IssueContext, type IssueRequest, type IssueField } from "./issue-context";
import { locateIssue } from "./errorPresentation";
import type { CallSpecSource, SourceIssue } from "./types";

export function IssueScope({ issues, request, includeIssue, children }: { includeIssue?: (issue: SourceIssue) => boolean; issues: SourceIssue[]; request?: IssueRequest; children: ReactNode }) {
  const [fields, setFields] = useState(new Map<HTMLElement, IssueField>());
  const summary = useRef<HTMLElement | null>(null);
  const focused = useRef<{ id: number; distance: number } | null>(null);
  const register = useCallback((element: HTMLElement, path: string[], id: string, control: boolean) => {
    setFields((current) => new Map(current).set(element, { path, id, control }));
    return () => setFields((current) => { const next = new Map(current); next.delete(element); return next; });
  }, []);
  const setSummary = useCallback((element: HTMLElement | null) => { summary.current = element; }, []);
  const visible = issues.filter((issue) => !includeIssue || includeIssue(issue) || [...fields.values()].some(({ path }) => path.length > 0 && path.length <= issue.path.length && path.every((part, index) => part === issue.path[index])));
  const fieldIssues = new Map<string, SourceIssue[]>();
  for (const issue of visible) {
    const id = closestField(fields, issue.path)?.[1].id;
    if (id) fieldIssues.set(id, [...(fieldIssues.get(id) ?? []), issue]);
  }
  useLayoutEffect(() => {
    if (!request) return;
    const match = closestField(fields, request.path);
    const field = match?.[0] ?? summary.current;
    const distance = match ? Math.abs(match[1].path.length - request.path.length) * 2 + (match[1].control ? 0 : 1) : Infinity;
    if (!field || (focused.current?.id === request.id && distance >= focused.current.distance)) return;
    const control = field.querySelector<HTMLElement>('input:not(:disabled), textarea:not(:disabled), button:not(:disabled), [tabindex="0"]') ?? field;
    field.scrollIntoView({ block: "nearest" });
    control.focus({ preventScroll: true });
    focused.current = { id: request.id, distance };
  }, [request, fields]);
  return <IssueContext.Provider value={{ issues: visible, fieldIssues, fields, register, setSummary, request }}>{children}</IssueContext.Provider>;
}
export function UnplacedIssues() {
  const context = useContext(IssueContext);
  const issues = context?.issues.filter((issue) => !closestField(context.fields, issue.path)) ?? [];
  if (!issues.length) return null;
  return <section ref={context?.setSummary} role="region" aria-label="Other issues in this tab" tabIndex={-1} className="mb-4 space-y-2 rounded-md border border-destructive/40 p-3 text-sm text-destructive outline-none focus-visible:ring-2 focus-visible:ring-ring">
    {issues.map((issue, index) => <p key={index}>{issue.reason}</p>)}
  </section>;
}

export function InspectorIssues({ source, nodeId, tab, issues = [], request, children }: { source: CallSpecSource; nodeId: string; tab: string; issues?: SourceIssue[]; request?: IssueRequest; children: ReactNode }) {
  return <IssueScope issues={issues} request={request} includeIssue={(issue) => { const location = locateIssue(source, issue.path); return location?.nodeId === nodeId && location.tab === tab; }}>{children}</IssueScope>;
}
