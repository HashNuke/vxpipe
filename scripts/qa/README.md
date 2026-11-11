# QA system services

These files run the QA checkout on this Ubuntu 26.04 host. Build the production
release with compiled assets first, then run as the checkout owner with Docker
access and sudo privileges:

```sh
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release vxpipe --overwrite
scripts/qa/install-services
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
