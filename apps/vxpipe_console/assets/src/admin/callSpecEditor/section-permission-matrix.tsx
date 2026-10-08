import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../components/ui/table";
import { ChoiceField } from "./editor-fields";
import { setSectionPermission } from "./variables";
import type { InspectorProps } from "./inspectorTypes";
export function SectionPermissionMatrix({ document, onChange, issues, agentKey }: InspectorProps & { agentKey?: string }) {
  const declared = document.source.call_variables?.sections ?? {};
  const agents = Object.entries(document.source.participants).filter(([key, value]) => value.type === "agent" && (!agentKey || key === agentKey));
  const sections = [...new Set([...Object.keys(declared), ...agents.flatMap(([, value]) => value.type === "agent" ? Object.keys(value.variable_permissions ?? {}) : [])])];
  if (!sections.length || !agents.length) return <p className="text-xs text-muted-foreground">Add a section and an agent to configure variable access.</p>;
  return <section className="space-y-3" aria-label="Section permissions"><h3 className="text-sm font-semibold">Section permissions</h3>
    <p className="text-xs text-muted-foreground">Agents can read a section, or read and write it. Dial-routing sections must remain read-only.</p>
    <Table><TableHeader><TableRow><TableHead>Section</TableHead>{agents.map(([key]) => <TableHead key={key}>{key}</TableHead>)}</TableRow></TableHeader><TableBody>
      {sections.map((section) => <TableRow key={section}><TableCell className="align-top font-medium">{section}{!Object.hasOwn(declared, section) && <span className="block text-xs text-destructive">Missing section</span>}</TableCell>{agents.map(([key, participant]) => {
        if (participant.type !== "agent") return null;
        const grants = participant.variable_permissions;
        const access = grants && Object.hasOwn(grants, section) ? grants[section] : undefined;
        return <TableCell key={key} className="min-w-40 align-top"><ChoiceField label={`${section} access for ${key}`} labelHidden path={["participants", key, "variable_permissions", section]} issues={issues} disabled={document.readOnly}
          value={access?.some((permission) => permission === "write") ? "write" : access?.includes("read") ? "read" : ""}
          choices={[{ value: "", label: "No access" }, { value: "read", label: "Read", disabled: !Object.hasOwn(declared, section) }, { value: "write", label: "Read and write", disabled: !Object.hasOwn(declared, section) }]}
          onChange={(value) => onChange(setSectionPermission(document, key, section, value === "write" ? ["read", "write"] : value === "read" ? ["read"] : undefined))} /></TableCell>;
      })}</TableRow>)}
    </TableBody></Table>
  </section>;
}
