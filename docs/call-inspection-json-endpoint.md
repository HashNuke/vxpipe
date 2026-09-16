# Database-backed call inspection JSON

Status: database query, response projection, authenticated HTTP resource and Console host are
implemented. Further live call interaction remains in the
[call debug console milestone](milestones/call-debug-console.md).

## Decision

The Console exposes one browser-facing JSON inspection resource at
`GET /calls/:call_id/inspection`. It is protected by the existing signed operator session and
`calls` authority. The response is the host payload used to populate `@vxpipe/core` for an ongoing
or ended call.

The resource reads only PostgreSQL-backed Calls data:

- the persisted call summary and complete `CallHistory`;
- the immutable prepared call and resolved participant plan selected at preparation;
- persisted usage observations and totals.

It does not inspect the live room process, download a call-details publication, list recordings,
or touch S3. For an ongoing call, the response therefore represents the newest facts archived to
the database. A browser that owns a live debug seat may apply RTVI updates after this baseline.

The existing routes remain distinct because they return different resources:

- `/calls/:call_id` is the server-rendered operator workspace. It currently combines persisted
  evidence with an optional in-memory live view and supporting artifact lists.
- `/calls/:call_id/details/:publication_id` downloads one immutable, versioned archival document.
  It is an artifact retrieval route and may use object storage.
- `/calls/:call_id/inspection` returns the complete, versioned database projection required by the
  reusable debug console.

Changing the HTML route to negotiate a second representation would couple LiveView routing and
the reusable data contract. Expanding the publication download would make an optional S3 artifact
the source of truth for ongoing inspection. The new resource instead reuses the
same Calls workflows beneath the existing UI while keeping one JSON data path.

## Responsibilities

`Vxpipe.Console.CallInspectionQuery` is the application workflow. It authorizes and loads the
persisted inspection first, then resolves that call's prepared plan, complete history and usage report
through the injected Console backend. It returns one typed result and owns partial-data policy.

`Vxpipe.Console.CallInspectionPresenter` is a pure conversion boundary. It converts the typed query
result to the versioned, snake-case JSON map. It does no I/O. This is the Elixir equivalent of a
narrow Ruby service/presenter split: the query coordinates use cases; the presenter owns the wire
shape. Smaller private projection functions stay grouped with the presenter while they share the
same reason to change.

`Vxpipe.Console.CallInspectionController` owns HTTP concerns only: status mapping and cache headers.

## Response contract

The initial response has schema version `1` and contains all call history currently persisted in
PostgreSQL. "Complete snapshot" describes the database read, not archive completion: the response
still reports `complete`, `incomplete` or `unconfirmed` honestly. It contains:

- call identity, lifecycle timestamps, terminal reason and derived duration;
- the selected room/incarnation identity when persisted facts establish it;
- the configured participant roster and authorized debug configuration from the immutable
  database resolved plan, preserving the runtime participant IDs used by history facts;
- normalized timeline entities for persisted transcripts, agent text, semantic activity and tool
  calls, with stable IDs, source sequences and revisions;
- the latest variable snapshot in the complete persisted history, or an explicit unavailable reason;
- database usage measurements whose attribution can be represented honestly;
- archive completeness.

Unknown fact kinds are retained as semantic activity rather than discarded. Raw RTVI receipts are
reported as unavailable because this endpoint does not persist them. Empty captured tool arguments
or results remain distinct from missing capture.

The response uses snake-case JSON to match existing Vxpipe HTTP contracts. The Console host adapter
validates and converts it to Core's camel-case TypeScript model; the reusable packages never fetch
this route directly.

The authenticated HTML host is `GET /calls/:call_id/console`. It loads the inspection resource,
creates a Core store/controller and renders `@vxpipe/react` without attaching live controls. A
refresh replaces the complete database baseline through Core's controller; a future RTVI adapter
can buffer and reapply only newer live updates during that replacement.

## Failure and security behavior

- A missing or cross-tenant call produces the same `404` response.
- Invalid requests produce `400`; unavailable database dependencies produce `503`.
- Responses set `Cache-Control: private, no-store`.
- The operator session remains server-side. API keys, provider credentials, signed artifact URLs,
  source policies and arbitrary private definition source never enter the response.
- The prepared plan is required because it supplies the runtime participant identities used by
  persisted facts. Usage unavailability is represented explicitly and does not convert an
  otherwise inspectable call into a false `404`.

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
