import { LockKeyhole } from "lucide-react";
import {
  CopyField,
  Disclosure,
  Pairs,
  SelectField,
  TextField,
} from "./FormControls";
import { authLabels, callbackUrl, type Draft } from "./fixtures";
import { DirectoryAuthenticationFields } from "./DirectoryAuthenticationFields";
import { McpSetupInformation } from "./McpSetupInformation";

export function AuthenticationFields({
  draft,
  update,
}: {
  draft: Draft;
  update: (patch: Partial<Draft>) => void;
}) {
  if (draft.preset.id !== "custom") return <><McpSetupInformation preset={draft.preset} /><DirectoryAuthenticationFields draft={draft} update={update} /></>;
  const customOAuth = draft.auth === "custom" && draft.customAuth === "oauth";
  const oauth =
    draft.auth !== "none" && (draft.auth !== "custom" || customOAuth);
  const text = (key: keyof Draft, label: string, extra = {}) => (
    <TextField
      label={label}
      value={String(draft[key])}
      onChange={(event) => update({ [key]: event.target.value })}
      {...extra}
    />
  );
  return (
    <>
      <McpSetupInformation preset={draft.preset} />
      <SelectField
        label="Authentication"
        value={draft.auth}
        onChange={(value) => update({ auth: value as Draft["auth"] })}
      >
        {Object.entries(authLabels).map(([key, label]) => (
          <option key={key} value={key}>
            {label}
          </option>
        ))}
      </SelectField>
      {draft.auth === "auto" && (
        <p className="mcp-auth-explanation">
          VxPipe checks whether sign-in is needed and discovers the server’s
          authentication settings.
        </p>
      )}
      {draft.auth === "none" && (
        <p className="mcp-auth-explanation">
          Connect without sending authentication credentials.
        </p>
      )}
      {draft.auth === "cimd" && (
        <div className="mcp-auth-details">
          <p>
            This server will read Vxpipe’s public client metadata to identify
            this installation.
          </p>
        </div>
      )}
      {draft.auth === "dcr" && (
        <div className="mcp-auth-details">
          <p>
            Register Vxpipe with the server automatically. Its client
            credentials will be managed with this connection.
          </p>
          <Disclosure title="Dynamic registration settings">
            {text("registrationUrl", "Registration URL", {
              placeholder: "Discovered from server metadata",
              type: "url",
            })}
            {text("registrationToken", "Initial registration token", {
              secret: true,
              hint: "Optional. Only needed if the registration endpoint requires a token.",
            })}
            <Pairs
              label="Registration parameters"
              singular="Registration parameter"
              pairs={draft.registrationParams}
              onChange={(registrationParams) => update({ registrationParams })}
            />
          </Disclosure>
        </div>
      )}
      {draft.auth === "custom" && (
        <>
          <SelectField
            label="Authentication type"
            value={draft.customAuth}
            onChange={(value) =>
              update({
                customAuth: value as Draft["customAuth"],
                headers:
                  value === "headers" && draft.headers.length === 0
                    ? [{ id: 1, name: "X-API-Key", value: "" }]
                    : draft.headers,
              })
            }
          >
            <option value="bearer">Bearer token</option>
            <option value="headers">API key / custom headers</option>
            <option value="basic">HTTP Basic</option>
            <option value="oauth">OAuth with my client</option>
          </SelectField>
          {draft.customAuth === "bearer" &&
            text("token", "Bearer token", {
              secret: true,
              placeholder: "Enter token",
            })}
          {draft.customAuth === "headers" && (
            <Pairs
              label="Request headers"
              singular="Header"
              pairs={draft.headers}
              onChange={(headers) => update({ headers })}
              secret
            />
          )}
          {draft.customAuth === "basic" && (
            <>
              {text("username", "Username", { autoComplete: "off" })}
              {text("password", "Password", { secret: true })}
            </>
          )}
          {customOAuth && (
            <>
              <SelectField
                label="Grant type"
                value={draft.grant}
                onChange={(value) => update({ grant: value as Draft["grant"] })}
              >
                <option value="authorization_code">
                  Authorization code with PKCE
                </option>
                <option value="client_credentials">Client credentials</option>
              </SelectField>
              {text("clientId", "Client ID", {
                placeholder: "Enter client ID",
              })}
              <SelectField
                label="Client authentication"
                value={draft.clientAuth}
                onChange={(value) =>
                  update({ clientAuth: value as Draft["clientAuth"] })
                }
              >
                <option value="client_secret_basic">
                  Client secret in Basic header
                </option>
                <option value="client_secret_post">
                  Client secret in request body
                </option>
                <option value="none">None · public client</option>
                <option value="private_key_jwt">
                  Signed JWT · private key
                </option>
              </SelectField>
              {["client_secret_basic", "client_secret_post"].includes(
                draft.clientAuth,
              ) &&
                text("clientSecret", "Client secret", {
                  secret: true,
                  placeholder: "Enter client secret",
                })}
              {draft.clientAuth === "private_key_jwt" && (
                <>
                  {text("privateKey", "Private key (PEM)", {
                    multiline: true,
                    secret: true,
                    placeholder: "Paste signing key for this OAuth client",
                  })}
                  {text("keyId", "Key ID", {
                    hint: "Optional JWT kid header.",
                  })}
                  <SelectField
                    label="Signing algorithm"
                    value={draft.algorithm}
                    onChange={(algorithm) => update({ algorithm })}
                  >
                    <option>RS256</option>
                    <option>ES256</option>
                    <option>PS256</option>
                  </SelectField>
                </>
              )}
              {draft.grant === "authorization_code" && (
                <>
                  <CopyField label="Callback URL" value={callbackUrl} />
                  <p className="mcp-inline-note">
                    <LockKeyhole size={14} aria-hidden />
                    PKCE (S256) and state are managed automatically.
                  </p>
                </>
              )}
            </>
          )}
        </>
      )}
      {oauth && (
        <Disclosure title="OAuth endpoints and scopes">
          <SelectField
            label="Endpoint configuration"
            value={draft.endpointMode}
            onChange={(value) =>
              update({ endpointMode: value as Draft["endpointMode"] })
            }
          >
            <option value="discovery">Discover automatically</option>
            <option value="manual">Enter endpoints manually</option>
          </SelectField>
          {text("issuer", "Authorization server URL", {
            type: "url",
            placeholder: "Optional issuer URL",
          })}
          {draft.endpointMode === "manual" && (
            <>
              {(!customOAuth || draft.grant === "authorization_code") &&
                text("authorizationUrl", "Authorization URL", {
                  type: "url",
                  placeholder: "https://auth.example.com/authorize",
                })}
              {text("tokenUrl", "Token URL", {
                type: "url",
                placeholder: "https://auth.example.com/token",
              })}
              {text("revocationUrl", "Revocation URL", {
                type: "url",
                placeholder: "Optional",
              })}
            </>
          )}
          {text("scopes", "Scopes", {
            placeholder: "Discovered from the server",
            hint: "Space-separated scopes, if the server requires specific permissions.",
          })}
          {text("resource", "Resource", {
            type: "url",
            placeholder: draft.endpoint || "MCP server URL",
            hint: "Defaults to this MCP server’s resource identifier.",
          })}
          {text("audience", "Audience", { placeholder: "Optional audience" })}
        </Disclosure>
      )}
      {draft.auth !== "none" && (
        <Disclosure title="Additional parameters">
          {oauth && (
            <>
              <p className="mcp-hint">
                Add provider-specific values. Vxpipe manages state, PKCE,
                redirect URI and grant parameters.
              </p>
              <Pairs
                label="Authorization request"
                singular="Authorization parameter"
                pairs={draft.authorizationParams}
                onChange={(authorizationParams) =>
                  update({ authorizationParams })
                }
              />
              <Pairs
                label="Token request"
                singular="Token parameter"
                pairs={draft.tokenParams}
                onChange={(tokenParams) => update({ tokenParams })}
                secret
              />
            </>
          )}
          {!(draft.auth === "custom" && draft.customAuth === "headers") && (
            <Pairs
              label="Additional MCP request headers"
              singular="Header"
              pairs={draft.headers}
              onChange={(headers) => update({ headers })}
              secret
            />
          )}
        </Disclosure>
      )}
    </>
  );
}
