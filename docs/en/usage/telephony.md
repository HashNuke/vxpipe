---
title: Telephony and transfers
description: Configure carrier services, route incoming calls and transfer within a call.
sidebar:
  order: 8
---

Telnyx and Twilio connect to the same call runtime used by browser participants.
Configure credentials and carrier application metadata, then publish a phone
route. A saved carrier API key alone does not route calls.

## Configure the public endpoint

Set the [Installation URL](configuration.md#installation-url) to the public HTTPS
origin. Copy the webhook URL shown for the selected service/scope into the carrier
dashboard. `TELEPHONY_HOST` can override that origin when ingress uses a separate
address. The proxy must accept WebSocket upgrades for media.

The Installation URL does not update provider dashboards. After changing it,
keep old callbacks reachable for active legs and update the provider configuration
for new calls.

## Telnyx

1. Open **Telnyx** in Platform Integrations and save the API key, public key and
   Voice API application ID. Tenants can inherit this connection.
2. Open Telnyx for a tenant to override its Voice application, or its credentials
   together with an application. Editing tenant credentials clears the application
   input and requires it to be entered again. Both sections save together.
3. Copy the webhook URL under **Voice application** into Telnyx, then assign the
   incoming numbers to that application. Inherited settings use the platform URL;
   either tenant override uses the tenant URL. Select webhook API version **2** and
   enable **Call cost in webhooks** on the application (`webhook_api_version: "2"`,
   `call_cost_in_webhooks: true`). Vxpipe does not change Telnyx settings.
   See the [Telnyx application settings](https://developers.telnyx.com/api-reference/call-control-applications/update-a-call-control-application).
4. Select **Telnyx** and a number on the incoming call spec's Entry connection,
   then publish it. In JSON, use `"service": "telnyx"`. The Voice API application
   ID belongs only in the Telnyx connection settings; never put an application ID
   or application name in a call spec.

A tenant can use the platform connection directly without registering a separate
phone service. A tenant application override takes precedence over the platform
application; tenant credentials require their own tenant application. Application-only
changes require tenant service write permission; credential controls follow the
role's separate credential permissions.

The shared application routes each called number to its tenant and published call
spec. Two published specs cannot claim the same number on that application.
Explicit tenant applications are dedicated: use inheritance to share the platform
application instead of copying its ID into an override.

**Use platform default** in Credentials retains the tenant application. To inherit
both settings, reset credentials first, then the application.

Telnyx includes the application as `connection_id` in its
[webhook payload](https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks). A dedicated tenant application
can still send to the platform URL if its webhook has not been updated: Vxpipe
selects that tenant and verifies the signature with its effective public key. A
tenant URL only accepts that tenant's routes. Shared application events also need
the called number to identify the tenant. Invalid credentials, unknown numbers
and ambiguous routes cannot start a call; retries cannot create a second call
after a number moves to another tenant. Active legs keep their original identity.

### Call costs

Signed `call.cost` events update the call's usage after it ends. Vxpipe records the
reported total, charge components and billed duration; retries do not add the same
charge again. Cost errors remain unavailable rather than appearing as zero. Keep
the original credential and its Telnyx public key available while final events
are arriving. Cost delivery must be enabled on the Voice API application.

## Twilio

Save the Account SID and Auth Token. Register a tenant telephony service using
the matching Account SID and exact saved credential ID. Trusted source-host
registration uses `mix vxpipe.telephony_service.register --tenant TENANT_KEY
--file service.json`; its metadata contains `name`, `ingress_key`,
`provider: "twilio"`, `provider_connection_id` (the Account SID) and `credential_id`.
Secrets belong in the credential record, not this metadata file.

Configure the service's incoming voice webhook in Twilio, then publish its phone
number route. Twilio uses its signed-request and media authentication path;
Telnyx's public-key field and scoped application form do not apply to it.

## Incoming and outgoing calls

The incoming number picker searches the selected provider account and marks
numbers already assigned to another published spec. Publication checks route
conflicts again; the browser's earlier availability result is not a reservation.

For outgoing calls, publish an outgoing spec with a valid originating service and
call the [create-call API](api-and-mcp.md#create-and-join-a-call). A successful dial
submission is not evidence that someone answered. Reuse the same idempotency key
after a lost response; a new key can create another real call.

## Transfers

An agent may transfer only to destinations explicitly allowed by its call spec.
The platform transfer tool requests the operation; spoken text such as “I am
transferring you” does not perform it.

An agent destination gets a fresh activation. A human destination can join through
the browser or a configured phone service. Private briefing and acceptance occur
before the caller is connected to the destination; phone acceptance can use the
configured press-1 flow. A variable-driven transfer number must satisfy the
declared schema and routing rules.

The caller remains in a controlled wait while the destination is prepared. A
rejection, timeout or failed destination can recover the original agent where
the transfer contract permits. Successful handoff retires the source activation,
including its live MCP resources. Transfer history settings select what the new
agent receives without expanding private-state visibility.

## Acceptance checklist

Call the real number from an external phone. Verify two-way audio, one tool
request, an accepted transfer, a failed transfer and hangup from each side.
Inspect the stored outcome and authorized recording/transcript. A signed webhook
or successful synthetic media test alone does not prove phone audibility.

Use [Operations](operations.md) to investigate callbacks, silent media and failed
handoffs. Development carrier harnesses are covered in
[Testing and verification](../development/testing.md#live-telephony).
