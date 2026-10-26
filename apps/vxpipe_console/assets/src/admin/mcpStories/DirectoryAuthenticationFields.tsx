import { CopyField, TextField } from "./FormControls";
import { callbackUrl, type Draft } from "./fixtures";

/** Directory configuration chooses the flow; only user-supplied credentials are editable. */
export function DirectoryAuthenticationFields({ draft, update }: {
  draft: Draft; update: (patch: Partial<Draft>) => void;
}) {
  const credential = (key: "token" | "username" | "password" | "clientId" | "clientSecret" | "privateKey", label: string, secret = true) =>
    <TextField label={label} value={draft[key]} secret={secret} onChange={event => update({ [key]: event.target.value })} />;

  if (draft.auth !== "custom") return <p className="mcp-hint">
    {draft.auth === "none" ? `Connect ${draft.preset.name} to make its tools available to your agents.` : `Continue to ${draft.preset.name} to authorize access.`}
  </p>;

  if (draft.customAuth === "bearer") return credential("token", "Bearer token");
  if (draft.customAuth === "basic") return <>{credential("username", "Username", false)}{credential("password", "Password")}</>;
  if (draft.customAuth === "headers") return <>{draft.headers.map(header =>
    <TextField key={header.id} label={header.name} value={header.value} secret onChange={event => update({
      headers: draft.headers.map(item => item.id === header.id ? { ...item, value: event.target.value } : item),
    })} />,
  )}</>;

  return <>
    {credential("clientId", "Client ID", false)}
    {["client_secret_basic", "client_secret_post"].includes(draft.clientAuth) && credential("clientSecret", "Client secret")}
    {draft.clientAuth === "private_key_jwt" && credential("privateKey", "Private key (PEM)")}
    {draft.grant === "authorization_code" && <CopyField label="Callback URL" value={callbackUrl} />}
  </>;
}
