---
title: Install with Docker
description: Run Vxpipe on your server using Docker and PostgreSQL.
sidebar:
  order: 1
---

Run Vxpipe behind a public HTTPS reverse proxy. Use PostgreSQL for persistent
application data and S3-compatible storage for call-detail files.

## Prepare the host

You need Docker, a PostgreSQL database reachable from the container, and a public
hostname. Configure your reverse proxy to forward HTTP and WebSocket traffic to
the application's internal port.

Use the image `ghcr.io/vxpipe/vxpipe`. Replace `VERSION` in the commands below with
the release tag you want to run. Pin a version or digest for repeatable deployments.

## Configure the application

Create a protected `vxpipe.env` file:

```dotenv
DATABASE_URL=postgresql://USER:PASSWORD@DB_HOST:5432/vxpipe
APP_HOST=voice.example.com
PORT=4000
SECRET_KEY_BASE=REPLACE_WITH_SIGNING_SECRET
VXPIPE_CREDENTIAL_KEY_ID=primary
VXPIPE_CREDENTIAL_KEYS={"primary":"REPLACE_WITH_BASE64_KEY"}
```

Replace each placeholder. `APP_HOST` is a hostname without a scheme or path.
Generate the signing secret and encryption key separately:

```shell
openssl rand -hex 32
openssl rand -base64 32
```

Use the first output for `SECRET_KEY_BASE` and the second inside the keyring JSON.
Keep these values across deployments and back up the keyring separately from
PostgreSQL. See [Configuration](../configuration.md) for object storage and other
optional settings. Add provider credentials through Console after startup.

## Migrate the database

Create the PostgreSQL database named in `DATABASE_URL`, then run this command
from the Docker host before starting or upgrading Vxpipe:

```shell
docker pull ghcr.io/vxpipe/vxpipe:VERSION
docker run --rm \
  --env-file ./vxpipe.env \
  --entrypoint /app/bin/migrate \
  ghcr.io/vxpipe/vxpipe:VERSION
```

Docker runs `/app/bin/migrate` inside a temporary container and removes the
container when it exits. The PostgreSQL data remains. Nothing needs installing
on the host beyond Docker. If PostgreSQL is in another container, add the same
`--network` option used by the application so both can reach it.

The image contains the versioned migrations from `vxpipe_persistence`. On a new
database they create the tables and indexes; on later runs Ecto applies only
versions missing from `schema_migrations`. Use the same image version and database
settings for migration and application startup. Start the app only if the command
succeeds; a migration error produces a nonzero exit status.

For an already-running container named `vxpipe`, the equivalent command using
that container's installed version and environment is:

```shell
docker exec vxpipe /app/bin/migrate
```

## Start the container

```shell
docker run --detach \
  --name vxpipe \
  --restart unless-stopped \
  --env-file ./vxpipe.env \
  --publish 127.0.0.1:4000:4000 \
  ghcr.io/vxpipe/vxpipe:VERSION
```

This binds port 4000 on the host's loopback interface. Point the host's HTTPS
reverse proxy at `http://127.0.0.1:4000`. If the proxy runs in Docker, connect both
containers to a shared network and use the application container's port.

Check `https://voice.example.com/healthz`, then open the Console and
[create your first account](../administration.md#first-account). The health endpoint
checks the HTTP handler; verify a real call to check providers and media.

Telephony requires reachable HTTPS/WSS callbacks. Browser calls also require a
working WebRTC media path; proxying the HTTP listener alone does not provide it.

## Upgrades and data

Back up the database, pull the selected image version, run its migrations and
replace the application container. Preserve PostgreSQL, object storage and
encryption keys. Follow the release's schema compatibility instructions when
rolling back.

Live calls belong to the running application process. Let active calls finish
before replacing it. See [Operations](../operations.md) for inspection and recovery.
