# Simplify tenant rows

- User requested removal of tenant IDs and Setup links from both Tenants and My
  tenants; remove tenant ID from the context heading above Dashboard too. Later
  requested recent-call rows align with the heading without horizontal padding.
- Removed ID/Setup rendering in the shared directory component, so both lists
  and the sample setup compatibility list use the same simplified rows. Kept
  created age beneath the name, with one block layout and no mixed-font baseline.
- Removed tenant key from production and Storybook context headings. Internal
  identity, URLs, backend query support and permission enforcement are unchanged.
- Removed unused metadata styles. A stale code rule added a separate 6px top
  margin to the tenant key; removing key rendering eliminates that mismatch.
- Recent-call row horizontal padding is now zero on desktop as it already was on
  mobile. Verified headings and row content align in rendered Chrome screenshots.
- Red: focused navigation test failed while tenant ID remained visible. Green:
  frontend suite 719 tests; updated heading tests 32/32; TypeScript and ESLint.
- Browser: Tenants and My tenants desktop/mobile, Dashboard desktop/mobile,
  including name-only heading and aligned recent-call rows. Screenshots in /tmp;
  no visual artifacts added to the repository. Required umbrella gates running.

- Follow-up: changed the new-tenant form label to “Give your tenant a name” and
  removed its duplicate subheading. Verified desktop/mobile and 33 focused
  form/navigation tests; creation behavior and error recovery remain covered.

- Required umbrella checks passed: format, compile with warnings as errors, strict
  Credo, 3,782 tests (132 excluded), and unused dependency check.
