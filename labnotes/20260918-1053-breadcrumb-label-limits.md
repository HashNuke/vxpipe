# Shared breadcrumb label limits

- Apply the user's per-part truncation request to the shared Breadcrumbs component,
  covering all admin headers and call details in compact and regular variants.
- Use a 24ch maximum width rather than slicing strings. The monospace header gets
  a predictable character-width budget, while complete text remains available to
  assistive technology, copying and native title tooltips. Existing flex shrinking
  can truncate further on narrow screens; links and current-location semantics stay
  unchanged.
- Red: two focused cases (compact/regular) failed because the maximum-width class
  was absent. Implementation adds that cap to linked and current labels only.
- Preserve all concurrent credential, call-directory and documentation edits.
- Green: 10 focused tests across Breadcrumbs, CallDetailsPage and tenant workspace
  layout. TypeScript, ESLint and CSS build pass.
- Browser verification: dark definitions, light services and dark call details,
  including long-content fixtures, at 1440×900 and 390×844. Both long linked call
  context labels cap independently at 173.39px (24ch in the current header font);
  the full DOM text and titles are intact. Mobile shrinks them further as needed;
  no document-level horizontal overflow was observed. Short labels stay unchanged.
- The initial full frontend run passed 124/125 tests, with the concurrent call-spec
  search accessible-name assertion failing. The initial root format check also
  found a trailing comma in that concurrent call-directory endpoint test. Neither
  file was changed for this task. Rechecks now pass all 125 frontend tests and the
  root format check. Warning-free compilation, strict Credo and unused-dependency
  checks pass. The full umbrella test run completed successfully with no failures
  across all eight applications (1,701 reported tests, 39 excluded). Gateway tests
  dominated the runtime; no backend changes were made to obtain the passing result.
