# Console scroll layout

## Goal

Allow the host to bound the console height. Keep the active tab within that boundary, with the conversation timeline scrolling above a composer that remains visible.

## Decisions

- `CallConsole.maxHeight` accepts any React CSS `max-height` value so an embedding page can account for its own header and surrounding layout.
- The console defaults to a 760 px working height bounded by the viewport.
- The workspace and main pane are non-scrolling containment layers. Each tab owns its vertical scrollbar; in Conversation, only the transcript scrolls while filters and composer remain fixed.
- The participant roster scrolls independently when it exceeds the bounded console height.

## Evidence

- Red: the focused React test failed because `CallConsole` did not apply the host-provided `maxHeight`.
- Green: the focused console suite passes 16 tests and `npm run check` passes.
- Browser, desktop: at 1280×900 the console is 760 px tall; the transcript has a 360 px client height and 668 px scroll height, while the composer and console bottoms remain aligned within 1 px.
- Browser, mobile: at 390×844 the participant rail retains its complete 53 px cards, the transcript scrolls in the remaining space, and the composer remains aligned to the console bottom.
- Browser, bounded tabs: at a 1280×640 viewport the 508 px console gives Metrics, Participants, and Variables 316 px scroll panes. Each pane's scroll height exceeds its client height without growing the console.
- Completion: `npm test` (21 tests), `npm run check`, Storybook production build, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, full `mix test`, and `mix deps.unlock --check-unused` all pass.
