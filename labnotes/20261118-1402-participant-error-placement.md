# Participant error placement

- The participant rename control registers the participant object path. Prefix-based matching incorrectly assigned hidden Models errors to that control and pulled them into unrelated tabs.
- Added exact issue-path matching for rename controls. Other fields retain parent/child fallback; tab inclusion uses the same matching rule. Actual key errors still appear on the rename control.
- Regression initially failed because Participant key had aria-invalid=true for a model error on Prompt. All 415 editor tests now pass, including tab switching, Models issue count, and actual key-error placement. TypeScript passes.
- Chromium desktop inspection confirms Model owns the error and Prompt has no invalid key or stray inline model error. Mobile inspection confirms the same error behavior; the existing fixed-width sidebar clips at 390px, outside this correction's scope.
- Format, warnings-as-errors compilation, strict Credo and unused-dependency checks pass. Full frontend and umbrella checks are running; release evidence follows separately.
