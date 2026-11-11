# QA system services

These files run the QA checkout on this Ubuntu 26.04 host. Build the production
release with compiled assets first, then run as the checkout owner with Docker
access and sudo privileges:

```sh
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release vxpipe --overwrite
scripts/qa/install-services
```

The installer packages the existing release as `vxpipe-qa:local`, installs both
units in `/etc/systemd/system`, enables them at boot and starts them:

- `vxpipe-qa.service` runs migrations, then the `vxpipe-qa` Docker container.
- `vxpipe-qa-proxy.service` runs Caddy for `https://vitrum.vxpipe.com` and redirects
  HTTP to HTTPS. Its certificate state stays in `/var/lib/vxpipe-qa-proxy`.

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
sudo systemctl status vxpipe-qa.service vxpipe-qa-proxy.service
sudo systemctl restart vxpipe-qa.service
sudo journalctl -u vxpipe-qa.service -n 50
docker stats --no-stream vxpipe-qa
```

For database migrations in the running container:

```sh
docker exec vxpipe-qa /app/bin/migrate
```
