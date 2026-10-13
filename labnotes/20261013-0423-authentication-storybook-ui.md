# Authentication Storybook UI

Scope: reusable Console components, ten composed pages and a connected mock journey.
Backend authentication, storage and authorization are explicitly held for user UI review.
The existing uncommitted authentication planning documents are preserved and extended.

## Checkpoints

- Read the existing Console shell, inventory, form, Storybook and test conventions.
  Reuse the established visual system; no new dependency or visual direction is needed.
- Checkout setup completed earlier in this session, including dependencies and assets.
- Started with focused red tests for account-category controls, tenant access caps and
  tenant picking. Import failures are expected before the new components exist.
  Corrected an initial command's duplicated relative directory before rerunning red.
- New UI uses deterministic synthetic fixtures and injected callbacks; no network,
  backend routes, credentials, local storage or real login session is introduced.

## Implementation and review

- Added reusable password/confirmation, role badge/selection, tenant assignment and
  permission components. Composed ten route previews and a connected mock journey
  from the same components. Storybook's index exposes 42 authentication stories:
  12 component, 25 page/state and five journey stories.
- Kept one role per user and protected built-in role kinds. An Admin can view peers
  and Superadmins but only mutate ordinary members; custom-role readers get a
  read-only directory. Tenant memberships cap the assigned-scope role grants.
- Injected callbacks keep persistence, credential verification and session revocation
  outside the UI. The mock models the feedback/redirect but stores no passwords.
- Initial red tests failed on missing modules; after implementation they passed.
  Page tests exposed a link whose cell role hid link semantics; moved the cell role
  to its container. Tests now cover protected account controls, direct denied routes,
  directory filters, reset confirmation, tenant picking/caps and user creation.
- The rendered pass found navigation retained scroll after long forms. Added a
  failing test (zero scroll calls on page navigation), then reset scroll only when
  pathname changes; filtering retains position. Widened desktop scope selects and
  corrected singular user-count wording in the same bounded correction pass.

## Verification

- Focused frontend suite: four files, 13 tests passed after the corrections.
- Full frontend regression suite after corrections: 77 files, 610 tests passed.
- All five required umbrella gates passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`
  (seed 811684, no failures) and `mix deps.unlock --check-unused`. The chained
  command exited zero. Default tests excluded live-provider lanes; no live test ran.
  Gateway's local WebRTC regression tests account for most of the roughly 13-minute run.
- TypeScript and ESLint passed. Storybook production build and Console assets build
  passed; no dependency or lockfile change. Storybook reports existing Node
  `module.register()` deprecation and large-chunk advisories.
- Headless Chrome through `agent-browser`, 1440×1000 and 390×844: inspected all ten
  pages via the connected flows, dark and light views, tenant selection and access
  editing, created user/role, reset mismatch and success, Admin's protected account,
  sign-out/login, save-failure feedback, and first setup automatically entering the Superadmin account.
  Checked browser errors (none), mobile horizontal width, and corrected scroll/label.
- Chrome initially could not start in the container sandbox; used `--no-sandbox`
  for this local fixture-only inspection. Initial generic `h1` waits timed out on
  Storybook's hidden “No Preview” heading; snapshots and the rendered story root
  confirmed loaded content. This was not an application failure.
- Mechanical UI detector returned no findings. Screenshots were kept as temporary
  inspection artifacts; fixtures contain only synthetic `example.test` identities.
- Changed documentation links and `git diff --check` passed. Existing uncommitted
  planning changes were preserved, with checkpoint P's implementation/evidence
  updated separately from the open user-approval and backend gates.

Review starts at `?path=/story/vxpipe-console-authentication-full-journey--superadmin`.
Run `bin/storybook`; the current checkout uses port 6009. See the
[review guide](../docs/development/authentication-storybook.md) for flows and mock limits.
Backend checkpoints and the deferred user UI review remain open at this checkpoint.
