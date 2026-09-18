# Console sample call catalog

The onboarding sample catalog is owned by `vxpipe_console`, because the examples, their defaults,
and the decision to offer them during first use are Console product policy. `vxpipe_calls` remains
limited to generic tenant, credential, Call Spec and publication workflows.

## Catalog

Version 1 contains three checked-in call specs:

- `sample-voice-conversation` — browser caller and one voice assistant.
- `sample-agent-handoff` — browser caller, receptionist and specialist agent.
- `sample-human-handoff` — browser caller, assistant and a separate browser support seat.

All three use the existing Deepgram STT/TTS selections and either the tenant's Google AI Studio or
Zenmux model credential. They require no telephony service, S3 bucket or external MCP server.

## Installation behavior

Installation is an explicit operator-authenticated, CSRF-protected action. The endpoint resolves the
durably bound demo tenant itself rather than accepting an arbitrary tenant identity from the browser.
Same-tenant installs are serialized so two tabs converge. Each call spec has a stable ID and source
digest:

- an absent sample is saved and published through the ordinary Calls APIs;
- an identical draft is published;
- an identical published call spec is returned unchanged;
- a call spec whose latest source differs is reported as a conflict and is never overwritten.

The response contains only sample IDs, names, statuses and installed revision numbers. Internal
failure terms and provider material are not returned.

## Verification

The catalog test parses every checked-in call spec with the production call-spec parser. A
real PostgreSQL/keyring test provisions tenant credentials, races two installs, retries after success,
and verifies exactly three published call specs at revision 1.
