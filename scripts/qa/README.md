# QA system services

These files run the QA checkout on this Ubuntu 26.04 host. Deploy only
committed code. Commit the changes first, then run as the checkout owner with
Docker access and sudo privileges:

```sh
bin/deploy-qa
```

The release is built from the checkout's files on disk, so `bin/deploy-qa`
refuses to start while any build input is uncommitted, and refuses to install if the tree or `HEAD` changed during the
build. It builds the workspace packages, applies the native dependency patches,
compiles production assets and the release, then runs
`scripts/qa/install-services`. The image records the deployed commit:

```sh
docker image inspect vxpipe:local \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
```

The installer packages the existing release as `vxpipe:local`, installs both
units in `/etc/systemd/system`, enables them at boot and starts them:

- `vxpipe.service` runs migrations, then the `vxpipe` Docker container.
- `caddy.service` runs the shared Caddy server and redirects HTTP to HTTPS.
  Its certificate state stays in `/var/lib/caddy`.

Caddy imports site files from `/etc/caddy/sites-enabled/*.caddy`. The installer
updates only `vxpipe.caddy`, serving `https://vitrum.vxpipe.com`; it preserves an
existing root Caddyfile and other services' site files. Add another site's config
to that directory and run `sudo systemctl reload caddy.service` to serve it.
Caddy's service lifecycle is independent of Vxpipe.

Compose supplies the checkout's `.env` to the container at runtime. The image
build context contains only the assembled release. The service files contain
placeholders resolved from the checkout path and installing user.

The app container has a 1 GiB memory limit and no extra swap allowance. It uses
host networking to preserve the existing HTTP and voice-media paths, with
`PORT=4001` behind Caddy. The local PostgreSQL socket is mounted read-only; the
container uses the checkout owner's UID/GID for peer authentication. These are
QA host settings, not a portable image build for other operating systems.

Systemd owns restart behavior. To inspect or restart the services:

```sh
sudo systemctl status vxpipe.service caddy.service
sudo systemctl restart vxpipe.service
sudo journalctl -u vxpipe.service -n 50
docker stats --no-stream vxpipe
```

For database migrations in the running container:

```sh
docker exec vxpipe /app/bin/migrate
```
