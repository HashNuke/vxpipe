---
title: Install with Docker
description: The intended container deployment contract and what remains before a runnable release.
sidebar:
  order: 1
---

**Planned delivery.** Vxpipe does not yet have a verified published application
image, container entrypoint or release migration command. This page defines the
intended installation. To run the current implementation, use
[Development workflow](../../development/local-development.md).

## Intended distribution

The intended image is `ghcr.io/hashnuke/vxpipe`, published from the main repository
to [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
Releases should have version tags and immutable digests. A deployment should pin
one reviewed version or digest; no available tag is claimed here.

The image should contain the production Elixir release and built Console assets.
Console, HTTP API, carrier signaling and platform MCP share one HTTP listener.
PostgreSQL is a separate service with persistent storage. Optional recordings
and call-detail files go to S3-compatible storage.

## Prepare the host

1. Provision PostgreSQL and its backup policy.
2. Create an encryption keyring and a stable signing secret. Supply them through
   the host's secret mechanism, separately from the database backup.
3. Configure a public HTTPS domain and a proxy that supports WebSocket upgrades.
4. Set `DATABASE_URL`, `APP_HOST`, `SECRET_KEY_BASE`,
   `VXPIPE_CREDENTIAL_KEY_ID` and `VXPIPE_CREDENTIAL_KEYS`. Set `PORT` if the internal
   listener should differ from `4000`. See [Configuration](../configuration.md).
5. Plan media networking separately: telephony uses public HTTPS/WSS callbacks;
   browser calls also require a reachable WebRTC media path. Publishing an HTTP
   port alone does not prove that path works.

## Expected release procedure

The first packaged release must supply exact, tested commands to pull its image,
run migrations once against the target database, start the service, and recover
an administrator account. Those commands must work without Mix or build tools
inside the runtime container. Until then, there is no supported `docker run`
recipe to copy from this page.

After startup, `/healthz` should return `ok`. This checks the HTTP handler, not
database, provider or media readiness. Complete first-account setup, connect
providers and run a call in both directions before accepting production traffic.

## Upgrades and data

Keep PostgreSQL, object storage and the encryption keyring across container
replacement. Call rooms and provider sessions are in memory; replacing the
application process does not preserve active calls. Stop new admission and let
active calls finish before a coordinated upgrade.

Back up before migrations. A previous image is not necessarily compatible with
the migrated schema; rollback instructions must accompany the release. Automatic
whole-call retention/deletion remains separate, unfinished delivery work.
