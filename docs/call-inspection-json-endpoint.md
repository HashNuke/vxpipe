# Database-backed call inspection JSON

Status: approved implementation design; implementation tracked in the
[call debug console milestone](milestones/call-debug-console.md).

## Decision

The Console exposes one browser-facing JSON inspection resource at
`GET /calls/:call_id/inspection`. It is protected by the existing signed operator session and
`calls` authority. The response is the host payload used to populate `@vxpipe/core` for an ongoing
or ended call.

The resource reads only PostgreSQL-backed Calls data:

- the bounded persisted call inspection page and its opaque older cursor;
- the immutable definition revision selected by the call;
- persisted usage observations and totals.

It does not inspect the live room process, download a call-details publication, list recordings,
or touch S3. For an ongoing call, the response therefore represents the newest facts archived to
the database. A browser that owns a live debug seat may apply RTVI updates after this baseline.

The existing routes remain distinct because they return different resources:

- `/calls/:call_id` is the server-rendered operator workspace. It currently combines persisted
  evidence with an optional in-memory live view and supporting artifact lists.
- `/calls/:call_id/details/:publication_id` downloads one immutable, versioned archival document.
  It is an artifact retrieval route and may use object storage.
- `/calls/:call_id/inspection` returns the bounded, versioned database projection required by the
  reusable debug console.

Changing the HTML route to negotiate a second representation would couple LiveView routing and
the reusable data contract. Expanding the publication download would make an optional S3 artifact
the source of truth for ongoing and paginated inspection. The new resource instead reuses the
same Calls workflows beneath the existing UI while keeping one JSON data path.

## Responsibilities

`Vxpipe.Console.CallInspectionQuery` is the application workflow. It authorizes and loads the
persisted inspection first, then resolves that call's exact definition revision and usage report
through the injected Console backend. It returns one typed result and owns partial-data policy.

`Vxpipe.Console.CallInspectionPresenter` is a pure conversion boundary. It converts the typed query
result to the versioned, snake-case JSON map. It does no I/O. This is the Elixir equivalent of a
narrow Ruby service/presenter split: the query coordinates use cases; the presenter owns the wire
shape. Smaller private projection functions stay grouped with the presenter while they share the
same reason to change.

`Vxpipe.Console.CallInspectionController` owns HTTP concerns only: cursor validation, status mapping
and cache headers.

## Response contract

The initial response has schema version `1` and contains:

- call identity, lifecycle timestamps, terminal reason and derived duration;
- the selected room/incarnation identity when persisted facts establish it;
- the configured participant roster and authorized debug configuration from the immutable
  database definition revision;
- normalized timeline entities for persisted transcripts, agent text, semantic activity and tool
  calls, with stable IDs, source sequences and revisions;
- the newest variable snapshot present in the loaded page, or an explicit unavailable reason;
- database usage measurements whose attribution can be represented honestly;
- archive completeness, an opaque older cursor and a UTC `as_of` instant.

Unknown fact kinds are retained as semantic activity rather than discarded. Raw RTVI receipts are
reported as unavailable because this endpoint does not persist them. Empty captured tool arguments
or results remain distinct from missing capture.

The response uses snake-case JSON to match existing Vxpipe HTTP contracts. The Console host adapter
validates and converts it to Core's camel-case TypeScript model; the reusable packages never fetch
this route directly.

## Failure and security behavior

- A missing or cross-tenant call produces the same `404` response.
- Invalid cursors produce `400`; unavailable database dependencies produce `503`.
- Responses set `Cache-Control: private, no-store`.
- The operator session remains server-side. API keys, provider credentials, signed artifact URLs,
  source policies and arbitrary private definition source never enter the response.
- Definition or usage unavailability is represented explicitly when the call inspection itself is
  available. It does not convert an inspectable call into a false `404`.

## Rejected alternatives

- Use the archived call-details download: it is optional, immutable, object-storage backed and not
  a cursor page for ongoing database history.
- Serialize LiveView assigns: they mix display state, live process inspection, recordings and
  publications and are not a stable client contract.
- Query Ecto schemas from Console: Calls already owns tenant authorization and repository ports.
- Make the controller build maps: that would duplicate conversion logic in every future transport
  and make the contract difficult to test without HTTP.

## Verification

Implementation requires focused query, presenter and endpoint tests, followed by Console and root
completion gates. Tests must use injected backends and assert that no live-inspection, call-details,
recording or object-storage operation occurs.
