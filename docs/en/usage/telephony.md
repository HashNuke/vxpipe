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

1. Save the Telnyx API key and its Ed25519 webhook verification public key at
   platform or tenant scope. The public key is required for phone operation.
2. In the tenant's Telephony settings, configure the Voice API application ID.
   Each scoped application belongs to one tenant. Set an E.164 outbound caller ID
   if the service will place calls or dial transfer destinations.
3. Use the webhook URL for that exact credential scope in Telnyx. Assign the
   intended incoming number to the Voice API application.
4. Select this service and number on the incoming call spec's Entry connection,
   then publish it.

A tenant Telnyx credential overrides the platform credential. An unreadable or
invalid tenant credential does not fall back to platform authority. The URL scope
selects the webhook verifier before new application routing is trusted.

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
