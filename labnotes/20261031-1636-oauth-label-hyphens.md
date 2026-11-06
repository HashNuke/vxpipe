# Single authentication dropdown

- User clarified that the full change is to remove the nested Authentication type dropdown and expose every method directly under Authentication, with normal hyphens in OAuth labels.
- The initial punctuation-only change was too narrow; expanded this checkpoint to cover the requested interaction.
- Kept the existing draft representation so discovery, credential validation, saved connections, and directory presets continue using their existing contracts. Only presentation maps the combined choice to auth/customAuth.
- Centralized display labels, including OAuth - Own client, for the dropdown and saved-connection header. Header selection still initializes X-API-Key when needed.
- Red: the focused test failed because the dropdown exposed Custom authentication instead of the four direct methods; saved-connection and bearer recovery expectations also failed before implementation.
- Green: all 90 MCP story tests pass, including method switching, saved OAuth/Basic selection, and bearer recovery. TypeScript check passes. Adjusted test queries to distinguish the Authentication tab from its combobox.
- Initially invoked frontend tests from the umbrella root, whose Vitest config only includes packages; reran from Console assets as required.
- Browser: inspected OAuth own-client at 1280x1000 and switched directly to API key/custom headers at 390x844. Single selector, fields, callback copy control, and footer render correctly.
- Full Console frontend suite: 119 files, 917 tests passed.
- Umbrella completion chain passed: mix format --check-formatted, mix compile --warnings-as-errors, mix credo --strict, mix test (seed 304258), and mix deps.unlock --check-unused. The media suites took several minutes; no code changes were needed.
- git diff --check passed. No commits created.
