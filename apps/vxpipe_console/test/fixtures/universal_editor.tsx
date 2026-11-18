import React from "react";
import { createRoot } from "react-dom/client";
import { CallSpecEditor } from "../../assets/src/admin/callSpecEditor/flow-editor";
import { EditorTheme } from "../../assets/src/admin/callSpecEditor/EditorTheme";
import { createEditorApi } from "../../assets/src/admin/callSpecEditor/editor-api";
import { parseSource } from "../../assets/src/admin/callSpecEditor/source";

const bootstrap = await fetch("/__editor/bootstrap").then(response => response.json());
const api = createEditorApi(bootstrap.tenant, "local-browser-acceptance", fetch);
let savedId: string | undefined;
createRoot(document.getElementById("root")!).render(
  <EditorTheme theme="dark"><CallSpecEditor
    snapshot={{ document: parseSource(JSON.stringify(bootstrap.source)) }}
    catalog={bootstrap.catalog} lookups={bootstrap.lookups}
    execute={api.execute} backHref="/" servicesHref="/"
    onNavigate={() => {}}
    onSaved={saved => { savedId = saved.callSpecId; Object.assign(window, { universalEditorSaved: saved }); }}
    onReload={signal => api.read(savedId!, signal)}
  /></EditorTheme>,
);
