import type { Draft } from "./fixtures";

function https(value: string) {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" && !url.username && !url.password && !url.hash
    );
  } catch {
    return false;
  }
}
export function validateDraft(draft: Draft): string | null {
  if (!https(draft.endpoint))
    return "Enter a complete HTTPS MCP server URL without embedded credentials or a fragment.";
  if (draft.auth === "none") return null;
  const oauth = draft.auth !== "custom" || draft.customAuth === "oauth";
  if (draft.auth === "custom") {
    if (draft.customAuth === "bearer" && !draft.token.trim())
      return "Enter a bearer token.";
    if (
      draft.customAuth === "basic" &&
      (!draft.username.trim() || !draft.password)
    )
      return "Enter a username and password.";
    if (draft.customAuth === "headers" && draft.headers.length === 0)
      return "Add at least one authentication header.";
    if (draft.customAuth === "oauth") {
      if (!draft.clientId.trim()) return "Enter your OAuth client ID.";
      if (
        ["client_secret_basic", "client_secret_post"].includes(
          draft.clientAuth,
        ) &&
        !draft.clientSecret
      )
        return "Enter your OAuth client secret.";
      if (draft.clientAuth === "private_key_jwt" && !draft.privateKey.trim())
        return "Enter your OAuth client’s signing key.";
    }
  }
  if (
    oauth &&
    draft.endpointMode === "manual" &&
    (!https(draft.tokenUrl) ||
      (draft.grant === "authorization_code" && !https(draft.authorizationUrl)))
  )
    return "Enter HTTPS authorization and token endpoints for the selected OAuth flow.";
  for (const url of oauth
    ? [draft.issuer, draft.revocationUrl, draft.registrationUrl, draft.resource]
    : []) {
    if (url && !https(url))
      return "Optional OAuth URLs must be complete HTTPS URLs.";
  }
  const groups = [
    draft.headers,
    ...(oauth
      ? [
          draft.authorizationParams,
          draft.tokenParams,
          ...(draft.auth === "dcr" ? [draft.registrationParams] : []),
        ]
      : []),
  ];
  for (const pairs of groups) {
    if (pairs.some((pair) => !pair.name.trim() || !pair.value))
      return "Complete each parameter’s name and value, or remove the empty row.";
    if (
      new Set(pairs.map((pair) => pair.name.toLowerCase())).size !==
      pairs.length
    )
      return "Use each parameter name only once in its section.";
  }
  const protectedHeaders = [
    "host",
    "content-length",
    "connection",
    "mcp-session-id",
    "mcp-protocol-version",
  ];
  if (!(draft.auth === "custom" && draft.customAuth === "headers"))
    protectedHeaders.push("authorization");
  if (
    draft.headers.some(
      (pair) =>
        protectedHeaders.includes(pair.name.toLowerCase()) ||
        !/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(pair.name) ||
        /[\r\n]/.test(pair.value),
    )
  )
    return "Use valid header names and values. Transport and generated authorization headers are managed by Vxpipe.";
  if (
    oauth &&
    [...draft.authorizationParams, ...draft.tokenParams].some((pair) =>
      [
        "state",
        "redirect_uri",
        "code",
        "code_verifier",
        "code_challenge",
        "code_challenge_method",
        "grant_type",
        "client_id",
        "client_secret",
        "resource",
        "scope",
      ].includes(pair.name.toLowerCase()),
    )
  )
    return "Use the OAuth fields above for standard parameters. State and PKCE are managed by Vxpipe.";
  return null;
}
