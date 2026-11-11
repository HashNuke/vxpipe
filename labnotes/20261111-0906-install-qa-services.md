# Install QA services

## Scope and decisions

- The user requested a 1 GB app container, system services for both the app and
  Caddy, and service scripts under `scripts/`. Implemented this profile under
  `scripts/qa/`; no Elixir application behavior or dependencies changed.
- Caddy was already a system service. Vxpipe was a native release running as a
  user service. Built `vxpipe-qa:local` from the existing production release and
  converted Vxpipe to a system service. Disabled and removed the replaced user
  unit after the container became healthy.
- The runtime image uses pinned Ubuntu 26.04 to match the release build host.
  The Docker build context is only the assembled release; no environment file
  or checkout secrets are copied into the image.
- Compose loads the QA `.env` for runtime use and preserves quoted dotenv
  values. No environment-file contents were inspected, printed or changed.
- Host networking preserves the existing HTTP, trusted loopback proxy and media
  paths. The PostgreSQL socket is mounted read-only and the container uses the
  checkout owner's UID/GID to preserve local peer authentication.
- Both units are installed in `/etc/systemd/system` and enabled at boot. Systemd
  runs the packaged migration command before starting the app and owns restart
  behavior. Caddy retains its certificate state and automatic HTTPS redirects.
- The container memory limit is 1 GiB. Setting its total memory/swap allowance
  to the same value gives it no additional swap allowance.
- This is local QA packaging. The public registry image and full delivery
  milestone remain incomplete.

## Verification

- Installer shell syntax, systemd unit verification and Caddy validation passed.
  Systemd emitted an unrelated host `system-xfs_scrub.slice` warning about its
  obsolete `CPUAccounting` setting; the new units were accepted.
- Built the image and checked native shared-library dependencies inside it: none
  unresolved. A packaged Silero inference ran successfully in a container with
  the same 1 GiB limit and networking disabled.
- Installed through `scripts/qa/install-services`. Migrations reported already
  up; the app and Caddy units are both active and enabled. The old user unit is
  inactive and no longer installed.
- Docker reports `Memory=1073741824`, `MemorySwap=1073741824` and no OOM kill.
  The container cgroup reports `memory.max=1073741824` and `memory.swap.max=0`.
  An idle sample used approximately 326 MiB; this is not a call-capacity test.
- HTTPS `/healthz` returns 200 and `ok`; HTTP redirects to HTTPS with 308.
- Rendered browser verification reached the setup form with the correct HTTPS
  origin and no browser errors. Chromium needed a task-scoped `--no-sandbox`
  launch flag because this host blocked its user-namespace sandbox; no host
  security settings were changed. No setup form was submitted.
- No new automated tests were added for Docker, systemd or the unchanged
  application code. Verification covered the installed configuration and artifact.

## Reference

[Docker Compose services](https://docs.docker.com/reference/compose-file/services/)
documents dotenv parsing, host networking and memory/swap limits.
