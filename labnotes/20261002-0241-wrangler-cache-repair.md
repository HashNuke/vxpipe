# Wrangler npx cache repair

## Symptom and evidence

- `npx wrangler login` repeatedly offered to install Wrangler 4.146.0, then
  returned to the prompt without starting the login flow.
- Existing npm debug logs showed failed `esbuild` and `workerd` postinstall
  scripts and exit status 1. The installed runtime was Node 26.8.1 with npm
  11.19.0; changing Node was not necessary.
- `npx --yes --foreground-scripts wrangler --version` exposed an esbuild
  binary validation failure with signal `SIGSEGV`.
- The unversioned Wrangler npx cache contained truncated native binaries:
  esbuild was 11,288,576 bytes versus 11,407,472 in a fresh cache; workerd
  was 11,440,128 bytes versus 134,687,800 in the fresh cache. The old workerd
  package metadata also differed from the newly resolved version.
- `npx --yes wrangler@4.146.0 --version` used a separate cache and succeeded,
  isolating the failure to the existing unversioned npx installation.

## Repair and decisions

- Renamed only the broken Wrangler cache directory inside npm's `_npx`
  directory, preserving it with a `.broken-20261002T024205Z` suffix.
- Re-ran the unversioned command to let npm create a fresh installation.
- Preserved the remaining npm cache and project dependencies. No runtime
  source, configuration, or lockfile change was needed.
- The original interruption or cause of truncation is unknown. The evidence
  supports a damaged extracted installation, not a Node compatibility diagnosis.

## Verification

- After repair, `npx --yes --foreground-scripts wrangler --version` printed
  `4.146.0` and exited successfully.
- `npx --yes wrangler@4.146.0 login --help` printed the login options and
  exited successfully.
- OAuth authorization remains for the user to complete in their browser.
- Subsequent plain `npx wrangler --version` and `npx wrangler login --help`
  both succeeded without an installation prompt.
- Confirmed Node, npm, and npx all resolve from the same mise Node 26.8.1
  installation. The user confirmed mise is the intended version manager.
- No application behavior changed, so umbrella runtime tests are not applicable.

## Reference

- npm documents `--foreground-scripts` as sharing install-script standard
  input, output, and error with the main process, useful for debugging:
  <https://docs.npmjs.com/cli/v11/using-npm/config/#foreground-scripts>.

## Follow-up: OAuth 403

- The user subsequently ran `npx wrangler login --device`. Wrangler started
  successfully, but its initial device authorization request returned HTTP 403.
- Inspected Wrangler 4.146.0's installed source: device authorization posts to
  `https://dash.cloudflare.com/oauth2/device/auth`; the authorization-code
  exchange posts to `https://dash.cloudflare.com/oauth2/token`.
- Diagnostic requests from this machine to the dashboard, device endpoint,
  and token endpoint returned HTTP 403, HTML, and `cf-mitigated: challenge`.
  Diagnostic POSTs used dummy parameters and no credentials. Only response
  status, content type, challenge classification, and selected metadata were
  printed; response bodies were not logged.
- Ordinary browser OAuth also needs the challenged token endpoint, so removing
  `--device` is not a verified solution for this network.
- An unauthenticated request to the API token verification endpoint at
  `api.cloudflare.com` returned an expected JSON authentication-header error
  (HTTP 400, code 6003) without a challenge. API token authentication is a
  supported alternative, but a valid token has not been provided or tested.
- Upstream reports document OAuth challenges from VPNs and remote VPS networks:
  <https://github.com/cloudflare/workers-sdk/issues/11081> and
  <https://github.com/cloudflare/workers-sdk/issues/15723>.
- The installation repair was verified; successful OAuth authorization was not.
