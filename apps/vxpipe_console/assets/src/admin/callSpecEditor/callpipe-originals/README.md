# Callpipe editor baseline

These are byte-for-byte copies of the approved Callpipe editor components and
stories at commit `2ea5ee0c503ef3690ad0d4e2139ee07bbbc985fd`. `manifest.json`
records their SHA-256 hashes. The page story came from the parent `pages/`
directory; the other files came from `pages/flow-editor/`.

The `.source` suffix keeps the initial copy checkpoint inert: these historical
modules refer to Callpipe-only controllers, translations and dependencies. They
are not imported or discovered as runnable Console stories. Each adapted component
will move into the editor as strict TypeScript; the git baseline preserves the
original markup and interaction design for review.

Test-call controllers, API/controller code, Lexical, knowledge and variable
retention components are not copied. References to those features in the original
component/story snapshots will be removed during adaptation. This baseline does
not expose them in the Console.
