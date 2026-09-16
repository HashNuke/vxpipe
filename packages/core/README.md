# @vxpipe/core

Framework-neutral public types for the Vxpipe browser client. This initial private package
defines the interface for the React prototype; it does not implement a production
RTVI decoder, WebRTC transport or call-admission client yet.

The `VxpipeClient` interface exposes snapshots/subscriptions and call, text and device actions.
Client implementations keep snapshot identity stable between updates and return an unsubscribe
function. React and Phoenix are not dependencies. Protocol/media adapters will live behind this
boundary in the call-console milestone.

Type-check and build from the repository root with:

```sh
npm exec --package=typescript@~5.9.3 -- tsc -p packages/core/tsconfig.build.json
```

The npm workspace also exposes `npm run build --workspace=@vxpipe/core`.
