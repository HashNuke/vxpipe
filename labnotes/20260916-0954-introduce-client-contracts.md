# Introduce client contracts

First package checkpoint: define the private `@vxpipe/core` contract before the React/Storybook
workspace checkpoint. It contains TypeScript declarations for snapshots, subscriptions, commands,
participants, messages, supplied spoken ranges, metrics and safe protocol events. No React,
Phoenix, runtime provider, protocol adapter or media implementation is included.

The types match the prototype boundary and remain provisional until the production adapter
milestone. Using one public contract keeps the UI from depending on protocol details. This is
a declaration-only change, so no new runtime test is warranted.

Verification: TypeScript 5.9 standalone package compilation and the complete workspace type check
passed. Umbrella format/compile/Credo/unused-lock checks passed; the bounded full suite passed
1,622 tests with zero failures and 39 exclusions. The prototype labnote records that test
command and the initial native-test concurrency failures. Browser-package generated outputs
are ignored. The separately staged React checkpoint supplies the executable UI and tests.
