# Telnyx v2 cost webhooks

Research confirmed that the existing receiver already accepts the v2 event envelope and validates ED25519 signatures over timestamp plus raw bytes. The provisioning script selected v2 on creation but did not detect version drift on existing applications. The `call.cost` event was ignored and had no durable billing path after live-leg cleanup.

Official sources:
- https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks
- https://developers.telnyx.com/api-reference/call-control-applications/update-a-call-control-application
- https://github.com/team-telnyx/openapi/blob/master/openapi/spec3.json (`CallCost`, `CallCostEvent`, `CallCostPart`)

Implementation:
- Keep the existing v2 lifecycle decoder and verifier. Dispatch cost events separately through the same authenticated HTTP entry points.
- Resolve durable telephony usage by provider leg/session and read the original service from the immutable call plan. Tenant routes must match the original tenant; application and credential identity remain pinned. No current phone-number search or live process is required.
- Store provider-reported final cumulative decimal total/component costs and billed milliseconds through the existing usage store. Component costs are included in the total. Currency comes from component evidence; ambiguous/missing total currency is rejected, not guessed. Provider error events preserve unknown cost.
- A stable receipt with a payload fingerprint precedes component writes. Exact retries deduplicate; changed deliveries conflict before changing components. Partial writes resume on retry, then request call-details publication. No new queue/process or billing table.
- Add a partial lookup index. Missing/ambiguous usage and unavailable credentials/storage return 503 for carrier retry. This does not recover events never delivered and depends on the carrier retry window while usage is being archived.
- Test provisioning now sets and repairs v2 and `call_cost_in_webhooks: true`. Usage and developer docs describe the settings and billing boundary.

Verification:
- Red: mocked provisioning retained v1/cost-disabled settings; five initial cost HTTP tests returned 404; persistence lacked the target lookup.
- Green: 24 focused Gateway tests (mounted cost and scoped lifecycle routes, decoder, verifier), 11 persistence usage tests, and both offline provisioning/hangup shell fixtures passed. These cover decimal amounts, signature/scope/application rejection, ended-call lookup, duplicate/conflicting writes and ambiguous targets.
- Applied the migration to the isolated test database; the persistence tests passed again with the new index.
- Root format check, warnings-as-errors compilation, strict Credo and unused-dependency check passed. No full suite or live telephony tests ran.
- Read the existing test application's flags through credentials resolved inside the running release, without reading an environment file: already v2, cost events disabled. No numbers, calls or orders were changed during that inspection.

Deployment evidence:
- Released `2d7f4fbb` to the QA service, including the shared-copy checkpoint `26c3d2aa` and modal hierarchy fix `a7ef5ebf`. Assets and the production release built successfully; the container image reports the expected revision.
- Both app and proxy services are active, the public health endpoint returns `ok`, and the deployed JavaScript/CSS contain the shared copy control. The container remains limited to 1 GiB.
- Enabled cost webhooks on the existing machine test application and read its configuration back: webhook API v2, cost notifications enabled, original webhook URL unchanged. No calls, number orders or live provider tests were run.
- Python's HTTP client received 403 on the public assets; curl verified both deployed files successfully. No environment files were read.
