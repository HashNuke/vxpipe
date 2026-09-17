# Remove calls description

## Decision

The definition-scoped Calls page no longer renders “Across all revisions…” or the publication
revision below its title. The selected definition already appears in the breadcrumb, while each call
row carries its own immutable definition revision. Repeating publication state consumed vertical
space without helping call selection.

`PageHeader` now accepts an optional description so a page can retain the shared title and divider
without inserting empty copy.

## Verification

- Focused tests first failed while the redundant copy was present, then all 12 page/journey tests
  passed after removal.
- Headless Chrome inspected **Admin / Definition calls / Narrow** at its 390 × 844 story viewport;
  the title leads directly into the call directory with no replacement text or overflow.
