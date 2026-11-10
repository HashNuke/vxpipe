---
title: Install on Railway
description: The intended Railway setup using the Vxpipe image and PostgreSQL.
sidebar:
  order: 2
---

**Planned delivery.** This is the target Railway configuration, not a verified
one-click template. The Vxpipe image, release migrations and hosted call acceptance
still need packaging work. Use the [source workflow](../../development/local-development.md)
to run the current application.

## Project layout

Use a PostgreSQL service and a Vxpipe application service running a pinned release
of the planned `ghcr.io/hashnuke/vxpipe` image. Keep them in the same project and
environment. Optional recordings and call-detail publications need S3-compatible
storage; the application container's filesystem is not their durable store.

Start with one application replica. Horizontal scaling requires an explicitly
verified call/media routing strategy; adding replicas does not move live rooms
between processes.

## Application variables

Assuming the database service is named `Postgres`, set:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Railway reference `${{Postgres.DATABASE_URL}}`. |
| `APP_HOST` | The application's public hostname, without `https://` or a path. |
| `SECRET_KEY_BASE` | A stable random secret of at least 64 bytes. |
| `VXPIPE_CREDENTIAL_KEY_ID` | The active encryption key ID. |
| `VXPIPE_CREDENTIAL_KEYS` | The JSON keyring described in [Configuration](../configuration.md). |

The application reads `PORT` and binds a public-host deployment on `0.0.0.0`.
If setting a fixed port, make the service's target port match. Provider API keys
are saved through Console after startup.

Configure a public HTTPS domain using
[Railway public networking](https://docs.railway.com/networking/public-networking).
Save that origin as the Installation URL during setup. `TELEPHONY_HOST` is needed
only when carrier ingress uses a different public origin or mount prefix.

## Deployment and checks

The packaged release must provide a migration command suitable for a Railway
pre-deploy step. Run it once before starting the new release; do not invent a
Mix command for a runtime-only image. The application's start command should be
the image's verified entrypoint.

Use `/healthz` as the
[Railway healthcheck path](https://docs.railway.com/deployments/healthchecks).
It returns HTTP 200 when the HTTP handler is running; it does not test PostgreSQL,
provider authorization or call readiness.

Before routing callers to this installation, verify:

- First account setup, login, credential save and call-spec publication.
- A Telnyx or Twilio webhook, bidirectional WSS audio and call termination.
- A tool invocation and a transfer using the intended provider combination.
- Browser WebRTC from an external network if browser calls are required.

Railway HTTPS routing by itself does not establish WebRTC media reachability.
The chosen ICE/TURN and network topology must be tested separately. No hosted
browser-call guarantee follows from a successful website or healthcheck request.

## Restart and recovery

Application replacement ends in-memory call resources. Drain calls before a
planned deployment and keep database backups and encryption keys independently
recoverable. Use the same image version with its matching schema; restore a
coordinated backup when a schema rollback cannot be performed safely. See
[Operations](../operations.md).
