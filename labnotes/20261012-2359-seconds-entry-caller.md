# Seconds inputs and Entry caller

- Audited timing inputs: max call duration and transfer attempt timeout in
  Advanced, transfer timeout in Human settings, outgoing ring timeout in Entry.
- Added a shared DurationField to display seconds and serialize rounded integer
  milliseconds. Fractions such as 25.6 become 25600; blank clears optional source
  values. Existing source values render in seconds without rewriting the source.
- Updated labels, hints, and local validation ranges to seconds. JSON/API field
  names and backend validation remain in milliseconds.
- Removed Entry's participant-key field. New incoming and outgoing UI specs both
  use caller. Existing/imported keys remain intact. Other participants retain
  their key editors and JSON editing remains available.
- Red tests verified missing seconds labels/conversion and the still-visible Entry
  key; outgoing creation tests failed on the old callee key. Green: 35 initial
  focused tests, then 597 full frontend tests after updating the route creation
  assertion. Added a loaded-source/fractional-seconds check and a seconds-range
  error regression; the latter first failed on the millisecond error message.
- Chrome inspection covered Advanced, incoming Entry, outgoing Entry, and Human
  timing; decimal input and existing 30-second ring default displayed correctly.
  Checked desktop and 390px mobile layouts. Existing key fields absent for Entry.
- Completion gates passed: format, warnings-as-errors compilation, strict Credo,
  3,574 umbrella tests with zero failures, and unused dependency check. Frontend
  full suite passed 597 tests; the final validation-message refinement passed
  114 focused tests, TypeScript, ESLint, and the Console asset build.
