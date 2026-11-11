# Rename system services

## Request and decision

- Use `vxpipe.service` for the app and `caddy.service` for the shared proxy.
  Neither name was registered on the host before this change.
- Rename the Compose project, container and local image to `vxpipe`, `vxpipe`
  and `vxpipe:local`. Keep the deployment in the QA worktree.
- Keep service templates and the installer in `scripts/qa/`. Caddy imports
  `/etc/caddy/sites-enabled/*.caddy`; Vxpipe owns one site file. The installer
  preserves the root Caddyfile on subsequent runs and leaves other sites alone.
- Remove the proxy's ordering dependency on Vxpipe so it can serve other apps
  independently. Move existing certificate state to `/var/lib/caddy` without
  inspecting its contents.

## Deployment and verification

- Stopped the old services before editing Compose because their stop command
  uses that file. Installed and enabled both new units, then removed the old
  unit files, stopped container, local image tag and proxy configuration.
- Shell syntax, rendered systemd units and Caddy configuration validate.
  Systemd reports an unrelated deprecated `CPUAccounting` option in the host's
  existing XFS scrub unit.
- Both new services are active and enabled. The old service names are absent
  and inactive. Caddy has no Vxpipe dependency.
- Startup migrations report "Migrations already up". The endpoint starts with
  the public HTTPS origin. Public `/healthz` returns HTTP 200 and `ok`;
  HTTP requests receive a 308 redirect to HTTPS.
- The origin certificate's SHA-256 fingerprint matches before and after the
  move, confirming that certificate state was preserved.
- Docker reports a 1,073,741,824-byte memory limit and the same total
  memory-plus-swap setting. The container's `memory.max` confirms the memory
  limit; the host has no swap configured. No OOM kill occurred.
- No application behavior changed, so validation used the installed services
  and HTTP boundary instead of adding tests or repeating the Elixir suite.
- No environment-file contents were inspected or changed. The main checkout
  remains clean on `main`; these changes belong to `qa`.
