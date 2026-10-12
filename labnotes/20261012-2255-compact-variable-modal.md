# Compact variable modal

- Name (shortened per follow-up) and Type are aligned inline fields. Enum? and
  Required? share one row; valid values use removable tags committed with Enter.
- Typed enum parsing uses the field type and lossless JSON number handling.
  Empty enums cannot be saved, duplicates/mistyped entries show errors, and
  changing type does not silently throw away existing tags.
- Removed nullable and numeric/length constraint controls from variable schemas,
  including nested fields. Saved schema keywords remain intact. Hidden constraint
  errors show focused JSON-editing guidance instead of an inaccessible control.
- Backend variable nodes default to nullable, including enums and array items;
  section roots remain objects. JSON-only nullable:false supports an explicit
  opt-out. Original source is not rewritten. Decision and implications are in
  docs/variable-nullability.md.
- Red: UI tests failed on old nullable/constraint controls and absent enum tags;
  Engine tests rejected implicit null and the nullable keyword. Error-navigation
  tests failed until hidden-constraint guidance was supplied.
- Green so far: 19 focused Engine tests and 112 focused frontend tests. Full UI
  suite exposed the old constraints/large-integer controls assumptions, which
  were updated to exercise tags and preservation rather than removed controls.
- Removed inherited dialog gap in addition to its content padding for compact
  spacing. Final desktop/mobile verification and completion gates pending.
- Final user refinements: Name replaces Variable name; Required precedes Enum on
  separate label-first checkbox rows. Name, Type, and Valid values align beside
  their controls on desktop and stack on mobile; checkbox labels stay inline.
  Removed the redundant section subtitle from the modal header.
- Browser verification: Chrome at 1280px and 390px; created string enum tags,
  saved/reopened a variable with its required flag and values intact, checked
  desktop alignment and mobile stacked fields. Widened the label column so
  Valid values stays on one line on desktop.
- Completion gates passed: format, warnings-as-errors compilation, strict Credo,
  3,574 umbrella tests (zero failures), unused dependency check, 596 frontend
  tests, TypeScript, ESLint, and Console esbuild. The final layout refinement
  also passed all 14 variable-panel tests, TypeScript, and ESLint.
