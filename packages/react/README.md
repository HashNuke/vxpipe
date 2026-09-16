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

The current prefixed stylesheet is prototype debt. The approved
[styling contract](../../docs/react-component-styling.md) migrates component rules to Tailwind v4
utilities colocated with TSX, retaining a small semantic-token stylesheet and generated npm CSS.
Complete that migration before adding more components or publishing a shadcn registry.

Exports include `CallConsole`, `Conversation`, `Composer`, `Participants`, `DeviceControls`,
`Variables`, `Metrics`, and the composable `Select` primitives. Device selection uses the
shadcn Select pattern backed by Radix UI, so the trigger and popup share package-owned styling,
keyboard behavior, focus management, and selected-state feedback. The composed console provides
their scoped styles/theme. Standalone pieces should be hosted in the same `.vx-console` theme
root. The Conversation filters can reveal raw RTVI events; application and server logs stay out
of this package contract. Turn metrics use Floating UI for their hover/focus tooltip; aggregate
metrics are grouped by room, room capability, participant and participant capability.

Run `npm run storybook` from the repository root. The [workspace README](../README.md) describes
the sample-only behavior, review states and checks. `stories/` contains application composition
and fixtures, excluded from the package build/exports. No packages are published in this checkpoint.
