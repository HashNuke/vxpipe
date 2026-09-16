# @vxpipe/core

Framework-neutral TypeScript state and public types for the Vxpipe browser client. It does not
depend on React, Phoenix, an endpoint URL, or an authentication implementation.

`createCallDetailsStore` hydrates a host-fetched `CallDetailsSnapshot`, reconciles revisioned
participant, timeline, variable, and metric updates, merges overlapping cursor pages, rejects stale
call incarnations, and keeps raw RTVI receipts append-only. Snapshot identity stays stable when an
update is ignored. `createCallDetailsController` wraps host-injected refresh and pagination
callbacks and buffers live updates across a baseline refresh.

The Console host owns URLs, authentication, and response fetching:

```ts
const initial = await callsApi.fetchDetails(callId);
const store = createCallDetailsStore(initial);
const controller = createCallDetailsController({
  store,
  loader: {
    refresh: (signal) => callsApi.fetchDetails(callId, { signal }),
    loadOlder: (cursor, signal) =>
      callsApi.fetchHistory(callId, { cursor, signal }),
  },
});
```

An ended call can omit the loader. An RTVI adapter can call `controller.apply(update)` for the live
edge of an attached call. Core never fetches a tenant endpoint itself.

The older combined `VxpipeClient`/`CallSnapshot` presentation contract remains temporarily exported
while the React package migrates to the split call-details and live-controls interfaces.

Type-check and build from the repository root with:

```sh
npm exec --package=typescript@~5.9.3 -- tsc -p packages/core/tsconfig.build.json
```

The npm workspace also exposes:

```sh
npm test --workspace=@vxpipe/core
npm run build --workspace=@vxpipe/core
```
