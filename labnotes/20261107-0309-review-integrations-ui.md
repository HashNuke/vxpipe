# Review integrations UI

- Scope: authorized combined inventory/category facade, production Integrations
  navigation, native credential-handler reuse and static custom MCP management.
  Browser OAuth, listed templates and callback draft recovery remain subsequent
  checkpoints. Existing Services URLs remain stable.
- Independent adversarial review reproduced four issues: native/MCP permissions
  were conflated; navigation remounted the directory and lost its previous page;
  saving a discovered anonymous endpoint lost its selected method; Refresh tools
  replaced configuration instead of using the catalog-only operation.
- Added red regressions through the production wrapper and inventory boundary.
  Split native credential write from tenant service write, retain component identity
  across navigation, persist the effective saved method, and send only generation
  plus refresh_tools for catalog refresh. All focused regressions passed.
- A second review found an inherited platform Edit button could be enabled for a
  platform writer without tenant credential permission, while the tenant wrapper
  refused it. The control now follows the tenant wrapper's actual capability;
  platform management remains available from Platform Integrations. A third granular
  role regression failed before the guard.
- First-render native rows lacked capabilities until a credential editor had been
  opened. Read-only users could never see the labels. Tests reproduce this for
  initial/local and outage inventories. Carry installed capability metadata on the
  inventory row and retain lazy credential/model settings; native logos use the
  known provider ID. The backend regression failed on missing capability metadata;
  local/remote/fallback projection now replaces untrusted directory labels with the
  installed registry subset. All 50 directory/API tests pass after the correction.
- After the presentation and permission corrections: all 974 frontend tests passed,
  TypeScript passed, ESLint had no errors (one pre-existing SetupDialog dependency warning),
  and 49 directory/API tests passed. Root format, compile warnings-as-errors,
  strict Credo and unused-dependency checks passed. Full umbrella run passed 4,886
  tests with zero failures and 201 exclusions before the final small capability
  projection; the affected 50-test facade lane and all four static gates pass
  after that correction.
- Headless Chrome inspected the production-component fixture at 1280x900 and
  390x844. Tools layout fits; Refresh tools and Disconnect returned to empty
  inventory. Native inherited override layouts also fit both sizes. Switching
  Custom headers → Bearer → Basic leaves the additional-headers editor empty.
  These fixture requests are in memory, without real HTTP credentials.
  The existing local Console server reports a configuration-change restart error;
  this pass does not establish authenticated backend/browser acceptance.
- No production backend source changed while the umbrella run was active. Later
  frontend presentation work passed 37 focused cases and the full 974-test suite.
  Independent adversarial review of the exact 42-file index found no remaining
  actionable findings. Unrelated and later work remains unstaged.
