# Installation URL workflow review

These stories began as a prototype for user review. The approved URL workflow now
has a [backend implementation](../installation-url.md): atomic setup persistence,
Superadmin settings, CIMD metadata and shared telephony/MCP origins. Storybook
retains deterministic fixtures. Outbound OAuth connection/token flows remain out
of scope.

## Review routes

- [First-run setup](http://localhost:6006/?path=/story/vxpipe-console-authentication-sign-in--setup):
  Configure URL → Setup SuperAdmin Account → Installation settings. The URL starts at the browser's
  origin, including its scheme and port. Back retains the current edits.
- [Installation settings](http://localhost:6006/?path=/story/vxpipe-console-settings-installation--default):
  change the URL and confirm the current/new addresses before the simulated save.
- [URL change confirmation](http://localhost:6006/?path=/story/vxpipe-console-settings-installation--change-url).
- [Save failure](http://localhost:6006/?path=/story/vxpipe-console-settings-installation--save-failure):
  the previous saved value and the current draft are retained.
- [Admin denied](http://localhost:6006/?path=/story/vxpipe-console-settings-installation--admin-denied):
  only the Superadmin fixture sees Installation in Settings.

The Installation group also provides saving, not-configured, loading,
unavailable/retry, ordinary-member-denied and light-theme stories. No real
credentials or external requests are used. Reloading resets the fixture.

## URL contract

Use the setup field name **Installation URL**. Store one canonical origin (scheme,
hostname, optional port), rather than a bare FQDN or a list of aliases. Existing
Console routes assume a root mount. The prototype strips page paths, queries and
fragments from pasted URLs and rejects credentials; HTTP is limited to
localhost/loopback development.
Choosing a URL does not configure DNS, HTTPS or reverse proxies.

The backend saves the URL/account atomically, enforces Superadmin authority and
allows existing installations to configure a missing URL in Settings. It supplies
CIMD and DCR metadata without trusting an arbitrary inbound Host header.

## Changing the URL and existing MCP authorizations

The [approved MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
requires matching redirect URIs and supports client metadata documents and dynamic
registration. For a future implementation:

- **CIMD:** the metadata document URL is the client ID. Moving that URL creates a
  different client identity; reconnect and obtain authorization for the new one.
  Keeping the old identity URL reachable is a distinct migration option requiring
  continued ownership of that domain, and is not the proposed default.
- **DCR:** [RFC 7592](https://www.rfc-editor.org/rfc/rfc7592.html) allows updating a
  client's registration where supported; support is optional. Updating redirects
  can preserve the client ID. Otherwise register a new client and obtain consent
  again. Do not assume the provider will retain or rotate secrets in every case.
- **Manual registration:** an operator can usually add the new callback to the
  existing provider application without replacing its client ID/secret.
- **Static API keys/bearer tokens:** changing Vxpipe's callback origin does not
  itself change those credentials.

A local URL change does not remotely revoke existing access/refresh tokens.
New client IDs cannot inherit another client's refresh tokens. Future migration
handling must retain the original registration identity and distinguish pending
reconnection from successful migration; do not simply relabel old credentials.
Outbound OAuth connection storage and migration execution remain outside this
workflow. Vxpipe's inbound OAuth issuer now also follows the saved Installation URL;
its explicit resource override remains supported.

Verification evidence is recorded in the [checkpoint labnote](../../labnotes/20261024-1756-instance-url-setup.md)
and the [URL and copy refinement labnote](../../labnotes/20261024-1835-setup-url-refinement.md).
