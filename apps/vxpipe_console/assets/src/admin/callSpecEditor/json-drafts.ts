import { createContext, useContext, useState, type Dispatch, type SetStateAction } from "react";

export type JsonDraft = { text: string; base: string };
export type JsonDrafts = Record<string, JsonDraft>;
export const JsonDraftContext = createContext<{ drafts: JsonDrafts; setDrafts: Dispatch<SetStateAction<JsonDrafts>> } | null>(null);

/** Keep unapplied JSON when inspectors unmount, including incomplete JSON. */
export function useJsonDrafts() {
  const context = useContext(JsonDraftContext);
  const [local, setLocal] = useState<JsonDrafts>({});
  const { drafts, setDrafts } = context ?? { drafts: local, setDrafts: setLocal };
  function setDraft(scope: string, draft: JsonDraft | undefined) {
    setDrafts((current) => {
      const next = { ...current };
      if (draft) next[scope] = draft;
      else delete next[scope];
      return next;
    });
  }
  return { drafts, setDraft };
}
