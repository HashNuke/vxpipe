# Vxpipe integration catalog

This directory is the source of truth for the public integration catalog.
The publisher/API lives in the sibling `../vxpipe-integrations-web` checkout
(relative to the Vxpipe repository root).

Add an integration by submitting a JSON definition in `integrations/`.

1. Copy `integrations/schema/template.json` to `integrations/<service-slug>.json`
   from the repository root, and set its `$schema` to `schema/schema.json`. Use a stable,
   lowercase slug with hyphens, for example `google-calendar.json`. The filename
   is the integration's identity; do not rename an existing file to change its
   display name.
2. Set the service name and official landing page. For MCPs, optionally provide
   `setup_url` and `documentation_url` as separate HTTPS links. Either, both or
   neither may be supplied. Omit missing links rather than using empty strings
   or null. Native provider definitions still require `documentation_url`.
   `summary` is optional. Keep it short and factual if provided.
3. Add one or more categories as `{ "id": "calendar", "name": "Calendar" }`.
   Reuse an existing category ID and name where appropriate. New categories are
   allowed. `ai` and `telephony` are reserved for built-in provider integrations;
   `connected` and `search` are navigation names and cannot be categories.
4. Fetch the landing-page HTML and inspect its `rel="icon"`, `shortcut icon`,
   `apple-touch-icon` and `apple-touch-icon-precomposed` links. Resolve relative
   links against the page URL. Set `icon_url` to the highest-quality usable icon
   actually declared there: prefer a safe, full-color SVG, otherwise the raster
   with the largest actual pixel dimensions (including ICO frames). Do not use
   an unrelated social-preview image, guess a larger URL, or use a monochrome
   pinned-tab mask when a full-color icon is available. Include the candidates
   and their dimensions in your pull request.
   Native providers whose landing page declares no usable icon may omit
   `icon_url`; the directory omits their logo and clients use a neutral icon.
   MCP definitions still require a declared icon. Do not use an empty string,
   null, guessed branding, or omit a supplied icon merely because a fetch fails.
5. Set `kind` and `connection` using the official integration documentation.
   For MCP, supply the complete HTTPS endpoint, `streamable_http` transport and
   authentication recipe. Endpoint paths are significant.
6. Optionally add `minimum_vxpipe_version`, such as `"0.2.0"`, when a minimum
   VxPipe release is known. Use a complete SemVer value without a `v` prefix.
   Omission means no additional version minimum is declared; it is not a claim
   that every client supports the service. An optional
   `maximum_vxpipe_version_exclusive` can express a known upper bound.
7. Set `availability` to `available`, `preview` or `retired`. Add `setup_notes`
   only for a concrete setup requirement. Mark unavailable integrations retired
   instead of reusing their filename for a different service.
   `setup_notes` is plain text (up to 1,000 characters), shown above a row of
   Setup and Documentation links. Notes and links are independently optional.
8. Validate the definitions and open a pull request with the official sources.

```sh
python3 -m pip install -r integrations/requirements-dev.txt
python3 integrations/scripts/validate.py
python3 -m unittest discover -s integrations/tests
```

MCP authentication recipes:

| Type | Fields |
| --- | --- |
| `oauth2` | `registration`: `discover`, `cimd`, `dcr`, or `preregistered`; optional `scopes` array |
| `bearer` | No additional fields |
| `api_key` | `header_name` |
| `basic` | No additional fields |
| `none` | No additional fields; only for explicitly anonymous servers |

OAuth registration hints do not replace server discovery or user consent.
Never include credentials, tokens, private keys, personal data or a shared OAuth
client secret. Definitions describe how a user connects; they contain no grants.

Built-in AI/telephony entries use `kind: "provider"` and
`connection: { "type": "builtin", "provider_id": "<existing-provider-id>" }`.
They require a minimum version and must identify an adapter already implemented
in VxPipe. Adding a definition does not add a native provider implementation.

The complete field contract is in `schema/schema.json`. Keep JSON files formatted with
two-space indentation and a final newline. The existing license applies to
contributions; third-party names and linked icons remain their owners' property.

Only the top-level `integrations/*.json` files are published. The `schema/`,
`scripts/`, `tests/` and `docs/` directories hold contribution support and evidence.
The publisher imports the catalog from one pinned commit of `HashNuke/vxpipe`
`main`; its existing signed push notifications queue catalog refreshes.
Catalog changes do not require rebuilding the publisher binary. See
[the source ownership and cutover notes](../docs/en/development/providers-and-integrations.md).
