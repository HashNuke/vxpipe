---
title: Install on Railway
description: Deploy Vxpipe with PostgreSQL and a public HTTPS domain on Railway.
sidebar:
  order: 2
---

Use a Railway project with a PostgreSQL service and a Vxpipe application service.
Optional call-detail files use S3-compatible object storage.

## Create the services

1. Add PostgreSQL to the project.
2. Add an application service using `ghcr.io/vxpipe/vxpipe:VERSION`, replacing
   `VERSION` with the release tag you want to deploy.
3. Keep both services in the same Railway project and environment.
4. Start with one application replica. Live calls belong to that process;
   additional replicas require call/media routing between instances.

## Set environment variables

Assuming the database service is named `Postgres`, configure the application:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Railway reference `${{Postgres.DATABASE_URL}}`. |
| `APP_HOST` | Public application hostname, without `https://` or a path. |
| `SECRET_KEY_BASE` | A stable random secret of at least 64 characters. |
| `VXPIPE_CREDENTIAL_KEY_ID` | The active encryption key name, for example `primary`. |
| `VXPIPE_CREDENTIAL_KEYS` | JSON such as `{"primary":"BASE64_KEY"}`, containing a base64-encoded 32-byte key. |

Generate the signing secret and encryption key separately:

```shell
openssl rand -hex 32
openssl rand -base64 32
```

Use the first output for `SECRET_KEY_BASE` and the second inside the keyring JSON.
Keep the values stable across deployments.

Vxpipe reads `PORT` and binds to `0.0.0.0` for a public hostname. If setting a fixed
port, make Railway's target port match. See [Configuration](../configuration.md)
for object storage and other optional settings. Provider credentials are saved
through Console after startup.

## Configure the public URL

Add a public HTTPS domain using
[Railway public networking](https://docs.railway.com/networking/public-networking)
and set `APP_HOST` to its hostname. Save the full HTTPS origin as the Installation
URL during first-account setup.

Set `TELEPHONY_HOST` only when carrier ingress uses a different public origin or
mount prefix. Railway's HTTPS routing supports the application's HTTP listener;
browser WebRTC still needs its own reachable media path.

## Deploy and check

Set the [pre-deploy command](https://docs.railway.com/deployments/pre-deploy-command)
to:

```shell
/app/bin/migrate
```

It uses the application environment to apply the database migrations bundled with
that image. It creates the schema on an empty database and applies pending
migrations on upgrades. A nonzero exit stops deployment. Use the image's default
entrypoint for the application service.

Set the [healthcheck path](https://docs.railway.com/deployments/healthchecks) to
`/healthz`. It returns HTTP 200 when the HTTP handler is running; it does not test
PostgreSQL, provider authorization or call readiness.

Open the Console and [create your first account](../administration.md#first-account).
Before accepting callers, check account setup, credential saving, a published call
spec, bidirectional audio, a tool invocation, transfers and hangup.

## Restart and recovery

Application replacement ends in-memory call resources. Let active calls finish
before a deployment. Keep database backups and encryption keys independently
recoverable; preserve object storage across application replacements.

Use the image version with its matching database schema. Follow the release's
rollback instructions when a database migration cannot be reversed safely. See
[Operations](../operations.md).
