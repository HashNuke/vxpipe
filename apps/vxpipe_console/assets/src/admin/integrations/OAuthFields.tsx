import { CopyField, Disclosure, Pairs, SelectField, TextField } from "../mcpStories/FormControls";
import type { McpDiscovery } from "./mcpDiscoveryApi";
import { oauthOptions, type ClientAuthentication, type OAuthGrant, type OAuthMethod, type OAuthValues } from "./oauthForm";

const grants: Record<OAuthGrant, string> = { authorization_code: "Authorization code with PKCE", client_credentials: "Client credentials" };
const clients: Record<ClientAuthentication, string> = {
  none: "None · public client", client_secret_basic: "Client secret in Basic header",
  client_secret_post: "Client secret in request body", private_key_jwt: "Signed JWT · private key",
};
export function OAuthFields({ method, values, discovery, onChange, issuer, onIssuerChange, listed = false, clientAuthConfirmed = true }: {
  method: OAuthMethod; values: OAuthValues; discovery: McpDiscovery | null;
  onChange: (patch: Partial<OAuthValues>) => void; issuer: string; onIssuerChange: (value: string) => void;
  listed?: boolean; clientAuthConfirmed?: boolean;
}) {
  if (method === "cimd") return <p className="mcp-hint">Vxpipe uses its client metadata and the server's discovered OAuth settings.</p>;
  if (method === "dcr") return <TextField label="Initial registration token" secret value={values.initialAccessToken}
    maxLength={8192} onChange={event => onChange({ initialAccessToken: event.target.value })}
    hint="Optional. Only needed if the registration endpoint requires a token." />;
  const choices = oauthOptions(discovery, values.grant);
  const browser = values.grant === "authorization_code";
  function changeGrant(value: string) {
    const grant = value as OAuthGrant;
    const methods = oauthOptions(discovery, grant).methods;
    onChange({ grant, clientAuth: methods.includes(values.clientAuth) ? values.clientAuth : methods[0] ?? "client_secret_basic",
      clientSecret: "", privateKey: "", keyId: "", ...(grant === "client_credentials" ? { authorizationParams: [] } : {}) });
  }
  function changeClient(value: string) { onChange({ clientAuth: value as ClientAuthentication, clientSecret: "", privateKey: "", keyId: "" }); }
  return <>
    {!listed && <SelectField label="Grant type" value={values.grant} onChange={changeGrant}>
      {!choices.grants.includes(values.grant) && <option value={values.grant} disabled>{grants[values.grant]} (unavailable)</option>}
      {choices.grants.map(grant => <option key={grant} value={grant}>{grants[grant]}</option>)}
    </SelectField>}
    <TextField label="Client ID" maxLength={2048} autoComplete="off" value={values.clientId} onChange={event => onChange({ clientId: event.target.value })} />
    <SelectField label="Client authentication" value={clientAuthConfirmed ? values.clientAuth : ""} onChange={changeClient}>
      {!clientAuthConfirmed && <option value="" disabled>Select the registered client authentication</option>}
      {!choices.methods.includes(values.clientAuth) && <option value={values.clientAuth} disabled>{clients[values.clientAuth]} (unavailable)</option>}
      {choices.methods.map(method => <option key={method} value={method}>{clients[method]}</option>)}
    </SelectField>
    {["client_secret_basic", "client_secret_post"].includes(values.clientAuth) && <TextField label="Client secret" secret maxLength={8192} value={values.clientSecret} onChange={event => onChange({ clientSecret: event.target.value })} />}
    {values.clientAuth === "private_key_jwt" && <>
      <TextField label="Private key (PEM)" secret multiline maxLength={16384} value={values.privateKey} onChange={event => onChange({ privateKey: event.target.value })} />
      <TextField label="Key ID" maxLength={256} value={values.keyId} onChange={event => onChange({ keyId: event.target.value })} hint="Optional JWT kid header." />
      <SelectField label="Signing algorithm" value={values.algorithm} onChange={algorithm => onChange({ algorithm })}>
        {!choices.algorithms.includes(values.algorithm) && <option value={values.algorithm} disabled>{values.algorithm} (unavailable)</option>}
        {choices.algorithms.map(value => <option key={value}>{value}</option>)}
      </SelectField>
    </>}
    {browser && discovery?.oauthClient && <><CopyField label="Callback URL" value={discovery.oauthClient.callbackUrl} /><p className="mcp-hint">Register this exact callback with your provider. Vxpipe manages PKCE and state.</p></>}
    {!listed && <><Disclosure title="OAuth endpoints and scopes">
      <TextField label="Authorization server URL" type="url" maxLength={2048} value={issuer} onChange={event => onIssuerChange(event.target.value)} />
      {browser && <TextField label="Authorization URL" type="url" maxLength={2048} value={values.authorizationUrl} onChange={event => onChange({ authorizationUrl: event.target.value })} />}
      <TextField label="Token URL" type="url" maxLength={2048} value={values.tokenUrl} onChange={event => onChange({ tokenUrl: event.target.value })} />
      <TextField label="Revocation URL" type="url" maxLength={2048} value={values.revocationUrl} onChange={event => onChange({ revocationUrl: event.target.value })} hint="Optional." />
      <TextField label="Scopes" maxLength={8192} value={values.scopes} onChange={event => onChange({ scopes: event.target.value })} hint="Space-separated scopes." />
      <TextField label="Resource" type="url" maxLength={2048} value={values.resource} onChange={event => onChange({ resource: event.target.value })} hint="Must match the MCP server URL." />
      <TextField label="Audience" maxLength={2048} value={values.audience} onChange={event => onChange({ audience: event.target.value })} hint="Optional provider-specific audience." />
    </Disclosure>
    <Disclosure title="Additional parameters">
      <p className="mcp-hint">Add literal provider-specific values. Vxpipe manages state, PKCE, redirect URI and grant parameters.</p>
      {browser && <Pairs label="Authorization request" singular="Authorization parameter" pairs={values.authorizationParams} onChange={authorizationParams => onChange({ authorizationParams })} />}
      <Pairs label="Token request" singular="Token parameter" pairs={values.tokenParams} onChange={tokenParams => onChange({ tokenParams })} secret />
      <Pairs label="Additional MCP request headers" singular="Header" pairs={values.headers} onChange={headers => onChange({ headers })} secret />
    </Disclosure></>}
  </>;
}
