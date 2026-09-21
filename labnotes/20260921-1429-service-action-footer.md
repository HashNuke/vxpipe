# Service action footer

The connected-service dialog placed Remove below a divider while Cancel, Test credentials and
Save were in the credential form. Desktop and 390px Chrome screenshots reproduced the split.
The form now owns one action footer: Remove stays at the left in the destructive color, and
Cancel/Test/Save stay grouped at the right. The Remove button remains `type="button"` and is
disabled while the form is busy. Its accessible name remains "Remove service" when the visible
label shortens to "Remove" on mobile. At widths below 360px, Test credentials shortens to Test
visually while keeping its full accessible name. The tenant-only Use platform service explanation
and action remain a distinct choice below the form.

The focused modal test first failed because no common action group existed. After the change, the
modal, credential form and scoped-service story suites passed (23 tests). TypeScript and lint
passed. The layout detector reported no findings. Rendered Chrome at 1440, 390 and 320px showed
all four actions on one row; at 320px their top coordinates matched and the page had no horizontal
overflow. The 390px light-theme view also kept readable labels and a visible Save control.
The full frontend suite passed (191 tests). The umbrella completion checks passed:
`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test` (all child suites green), and `mix deps.unlock --check-unused`.

This is a layout and action-placement change. Removal still invokes its existing callback; no
credential payload, call path, persistence or provider behavior changed.
