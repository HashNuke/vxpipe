# Compile MCP prerequisites during setup

A fresh acceptance checkout failed in bin/setup while compiling the patched ExMCP:
Plug.Conn was not loaded. The script named only ex_mcp, which Mix deliberately
compiles without bringing its prerequisite dependency tree up to date. The same
command existed in CI, where the same fresh-build failure applies.

Read mix help deps.compile: --include-children is the supported way to compile a
named dependency with its prerequisites. Preserve the patch-before-compilation
order and use that option for dev/test setup and CI. Update the existing setup
boundary tests to require this mode. Both focused tests fail before the script
change, matching the observed fresh-checkout failure. No dependency, patch content,
lockfile or provider configuration changes are needed.

All 33 setup tests pass. Independent source review confirms clean and warm
compilation semantics from the installed Mix implementation and finds no code
blockers. Clarified that CI caches dependency source rather than compiled output;
its fresh build has the same prerequisite failure. The real checkout retry now
passes all steps: patched dependency compilation with prerequisites in dev/test,
frontend installation/build and both isolated database migrations. Setup preserves
the checkout identity from the failed first attempt and reports readiness. No
lockfile changes were produced. The exact fix is integrated into the main checkout.
All 33 setup tests pass there, followed by all five root gates: format, warnings-as-
errors compile, strict Credo, 4,987 tests with zero failures and 235 excluded
(seed 999227), and unused-dependency verification. Browser consent and callback
acceptance remain separate, unfinished work.
