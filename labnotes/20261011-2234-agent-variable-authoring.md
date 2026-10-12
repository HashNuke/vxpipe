# Agent and variable authoring

## Scope and decisions

- New added agents and the initial agent in incoming/outgoing specs start with
  an empty prompt. Existing validation already rejects empty and whitespace-only
  prompts, so no new save-validation mechanism is needed.
- Section names appear as headings. Adding and editing sections use a staged
  modal for the name and schema constraints. Cancel makes no source changes;
  saving a rename continues to update permissions and dial references atomically.
- Section constraints appear as wrapping key:value badges below the heading.
  Removed the old inline name field and constraints disclosure.
- Removed Additional properties controls. New sections and newly selected object
  variable types use `additionalProperties: false`. Existing unedited schema
  values and nested variables remain intact.
- Reused the existing Dialog, Badge, schema fields and issue-navigation system.
  Section errors open the modal at the appropriate field; historical sections
  remain inspectable with editing disabled.
- The user briefly proposed a list-section toggle, then confirmed a preference
  for the existing single-object section after clarifying that enumeration means
  allowed values. Kept the backend contract unchanged and added no list toggle.

## Verification

- Inspected the existing Storybook page in rendered Chrome before editing.
- Red first: 10 expected failures for seeded prompts, missing section dialogs,
  headings/tags, and the removed Additional properties control. After the
  implementation, all 54 focused tests passed.
- Updated route tests to supply author-written prompts before valid saves, and
  verified that initial creation cannot save a blank prompt. Updated the section
  Storybook interaction to use the new modal.
- Full frontend suite: 570 tests passed; TypeScript and ESLint passed. Root
  format, warnings-as-errors compilation, strict Credo and unused-lock checks
  passed. Full umbrella suite passed: 3,564 tests, zero failures, 128 existing
  integration/live exclusions. Final whitespace validation passed.
- Chrome inspection at 1440x960 and 390x844 passed: an added agent had a blank
  prompt and saving showed the validation failure; a section was added through
  the desktop modal; the nested-variable story displayed a required-field badge;
  editing a section inside the phone sheet opened the modal and saved its rename.
  Controls fit the dialog and the sidebar retained its variable rows.
- Storybook reloads on documentation/labnotes edits. Reloaded the story when this
  reset an inspection state; browser commands using fresh element references
  confirmed the actual interactions after the reload.
