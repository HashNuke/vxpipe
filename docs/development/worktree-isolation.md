# Worktree isolation

Vxpipe prepares each checkout with its own development state so you can work on
multiple branches side by side. Run `bin/setup` in each checkout; it prints the
assigned Console and Storybook URLs. See [local development](local-development.md)
for prerequisites and startup commands.

## What stays separate

| State | How Vxpipe isolates it |
| --- | --- |
| Checkout identity | Ignored `.vxpipe/worktree.json` records the identity, database names and assigned ports. |
| Databases | Each checkout gets separate development and test databases. Setup checks ownership before using them. |
| Local configuration | Setup creates `.env` when needed and preserves an existing file on reruns. |
| Dependencies and generated files | Build outputs, frontend dependencies and temporary test files stay local to the checkout. |
| Servers and browser sessions | Console and Storybook get reserved ports; Console cookies distinguish checkouts on the same hostname. |

The identity belongs to the checkout, so switching its Git branch keeps its
existing databases and ports. Ordinary root and child Mix commands read the
saved development/test defaults without a shell activation step.

## Day-to-day use

Rerun `bin/setup` when dependencies or migrations change. It preserves the
checkout identity, existing secrets, database data and port assignments.

To assign new ports, stop that checkout's servers and run:

```shell
bin/setup --reassign-ports
```

Explicit settings such as database URLs, `PORT` and `STORYBOOK_PORT` take
precedence over assigned defaults. Keep those overrides distinct when running
several checkouts. Setup reports conflicting databases, copied metadata or
shared build directories instead of silently taking over another checkout's
state. Retired databases require explicit cleanup.

Live-provider testing has separate shared ownership rules; see
[live provider tests](live-provider-tests.md).

## Where to look next

- [Setup command](../../bin/setup): coordinates checkout preparation.
- [Checkout metadata](../../bin/lib/worktree_state.py): identity and saved defaults.
- [Database setup](../../bin/lib/setup_database.py): database ownership and initialization.
- [Port allocation](../../bin/lib/worktree_ports.py): reservations shared across checkouts.
- [Runtime configuration](../../config/runtime.exs): how development/test commands consume the defaults.
