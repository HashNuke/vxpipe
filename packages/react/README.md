# @vxpipe/react

Private React component package for Vxpipe. Uses only the public `@vxpipe/core` contract and
host-supplied props; it imports no protocol SDK, Phoenix API or application route.

```tsx
import { CallConsole } from "@vxpipe/react";
import "@vxpipe/react/styles.css";

<CallConsole client={client} />;
```

Dark mode is the default. Pass `theme="light"` for a light surface. The host owns client
creation and disposal; components subscribe/unsubscribe without taking ownership of its lifetime.
The public component contract remains provisional while the UI is prototyped.

Exports include `CallConsole`, `Conversation`, `Composer`, `Participants`, `DeviceControls`,
`Metrics` and `EventLog`. The composed console provides their scoped styles/theme. Standalone
pieces should be hosted in the same `.vx-console` theme root. `EventLog` displays RTVI events
only; it is not an application or server log viewer.

Run `npm run storybook` from the repository root. The [workspace README](../README.md) describes
the sample-only behavior, review states and checks. `stories/` contains application composition
and fixtures, excluded from the package build/exports. No packages are published in this checkpoint.
