# @vxpipe/react

Typed React components for Vxpipe. The package renders host-supplied `@vxpipe/core` call details
and imports no protocol SDK, Phoenix API, endpoint, authentication code, or application route.

```tsx
import {
  createCallDetailsController,
  createCallDetailsStore,
} from "@vxpipe/core";
import { CallConsole } from "@vxpipe/react";
import "@vxpipe/react/styles.css";

const initialDetails = await callsApi.fetchDetails(callId);
const store = createCallDetailsStore(initialDetails);
const history = createCallDetailsController({
  store,
  loader: {
    refresh: (signal) => callsApi.fetchDetails(callId, { signal }),
    loadOlder: (cursor, signal) =>
      callsApi.fetchHistory(callId, { cursor, signal }),
  },
});

<CallConsole controller={{ details: history, history }} />;
```

The same component renders an ongoing or ended remote call without joining an RTVI session. Add a
host-created `live` controller to enable the call, text, microphone, speaker, and device controls:

```tsx
<CallConsole controller={{ details: history, history, live }} />;
```

Dark mode is the default. Pass `theme="light"` for a light surface. The host owns controller
creation and disposal; components subscribe and unsubscribe without taking ownership of its
lifetime. All public source and declaration output is TypeScript.

The current prefixed stylesheet is prototype debt. The approved
[styling contract](../../docs/react-component-styling.md) migrates component rules to Tailwind v4
utilities colocated with TSX, retaining a small semantic-token stylesheet and generated npm CSS.
Complete that migration before publishing a shadcn registry.

Exports include `CallConsole`, `Conversation`, `Composer`, `Participants`, `DeviceControls`,
`Variables`, `Metrics`, and the composable `Select` primitives. Device selection uses the shadcn
Select pattern backed by Radix UI. Turn metrics use Floating UI for hover and focus tooltips.

Run from the repository root:

```sh
npm ci
npm ci --prefix apps/vxpipe_console/assets
npm test --workspace=@vxpipe/react
npm run build
npm run storybook
```

This single Storybook contains both the reusable debug-console stories and the Console-owned
operator administration stories. Use **Admin / Full journey** for the linked tenant-to-call review
flow. The [workspace README](../README.md) describes the review states and checks. `stories/`
contains application composition and typed mock endpoint/RTVI fixtures; it is excluded from package
exports. No packages are published in this checkpoint.
