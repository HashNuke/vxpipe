import { useState } from "react";
import { CallSpecEditor } from "../callSpecEditor/flow-editor";
import { EditorTheme } from "../callSpecEditor/EditorTheme";
import { pageSnapshot } from "../callSpecEditor/page-fixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { VoiceCatalogContext } from "../voiceCatalog";
import { storyVoiceCatalog } from "../voiceCatalogFixtures";
import type { Theme } from "../authentication/types";
export function NavigationEditor({ theme, backPath, onNavigate, readOnly = false }: { readOnly?: boolean; theme: Theme; backPath: string; onNavigate: (path: string) => void }) {
  const [revision, setRevision] = useState(3);
  const snapshot = pageSnapshot("default");
  snapshot.document = { ...snapshot.document, readOnly };
  return <VoiceCatalogContext.Provider value={storyVoiceCatalog}><EditorTheme theme={theme}>
    <CallSpecEditor snapshot={snapshot} catalog={modelCatalogFixture} lookups={{ phoneNumbers: async () => ({ numbers: [], nextPage: null }), telephonyServices: [], credentialNames: {}, mcpIntegrations: [] }} onReload={async () => pageSnapshot("default")} backHref={`#${backPath}`} servicesHref={`#${backPath.replace(/call-specs$/, "services")}`} onNavigate={path => onNavigate(path.replace(/^#/, ""))}
      execute={async request => { if (request.action === "publish") return { status: 200, revision: request.revision }; const next = revision + 1; setRevision(next); return { status: 201, revision: next, callSpecId: "appointments" }; }} />
  </EditorTheme></VoiceCatalogContext.Provider>;
}
