# Tool response status

## Goal

Show a tool response's HTTP status on the Response tab so developers can scan the outcome before opening that panel.

## Decisions

- Render the numeric code as a compact badge only when `responseStatus` is available.
- Use success and error token colors for 2xx/3xx and 4xx/5xx responses; leave other codes neutral.
- Keep the tab's accessible name as `Response`; the badge is visual metadata with its full `HTTP <code>` value in the title.
- Remove the duplicate status from the response panel content.

## Evidence

- Red: the focused console test failed because the Response tab did not contain the status badge.
- Green: the focused console suite passes 16 tests and `npm run check` passes. Tests cover 200, 503, and 204 badges, response bodies, and empty responses.
- Browser: inspected expanded 200 and 503 responses at 1280×900 and the 503 response at 390×844 in headless Chrome. The badge remains legible in both layouts and the status is absent from the panel body.
- Completion: `npm test` (21 tests), `npm run check`, Storybook production build, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, full `mix test`, and `mix deps.unlock --check-unused` all pass.
