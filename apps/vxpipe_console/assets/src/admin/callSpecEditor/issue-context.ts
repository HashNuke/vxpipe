import { createContext, useContext, useId, useLayoutEffect, useMemo, useRef } from "react";
import type { SourceIssue } from "./types";
export type IssueRequest = { id: number; path: string[] };
export type IssueField = { path: string[]; id: string; control: boolean };
type IssueContextValue = {
  issues: SourceIssue[];
  fieldIssues: Map<string, SourceIssue[]>;
  fields: Map<HTMLElement, IssueField>;
  register: (element: HTMLElement, path: string[], id: string, control: boolean) => () => void;
  setSummary: (element: HTMLElement | null) => void;
  request?: IssueRequest;
};
export const IssueContext = createContext<IssueContextValue | null>(null);
const prefix = (a: string[], b: string[]) => a.length <= b.length && a.every((part, index) => part === b[index]);
export function closestField(fields: Map<HTMLElement, IssueField>, path: string[]) {
  // A newly opened dialog owns a duplicate path ahead of its underlying card.
  const entries = [...fields].reverse();
  return entries.filter(([, field]) => prefix(field.path, path)).sort((a, b) => b[1].path.length - a[1].path.length || Number(b[1].control) - Number(a[1].control))[0]
    ?? entries.filter(([, field]) => prefix(path, field.path)).sort((a, b) => a[1].path.length - b[1].path.length || Number(b[1].control) - Number(a[1].control))[0];
}
export function useIssueField(path: string[], explicit: SourceIssue[] = [], control = true) {
  const id = useId();
  const context = useContext(IssueContext);
  const ref = useRef<HTMLDivElement>(null);
  const key = JSON.stringify(path);
  const stablePath: string[] = useMemo(() => JSON.parse(key), [key]);
  const register = context?.register;
  useLayoutEffect(() => {
    if (register && ref.current) return register(ref.current, stablePath, id, control);
  }, [register, stablePath, id, control]);
  const errors = context
    ? (context.fieldIssues.get(id) ?? [])
    : explicit.filter((issue) => JSON.stringify(issue.path) === key);
  return { ref, errors };
}
export function useIssueRequest() { return useContext(IssueContext)?.request; }
