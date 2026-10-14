# Service tooltip and empty-state refinement

## Arrow alignment

- The shared shadcn/Radix tooltip is already backed by Floating UI through `@radix-ui/react-popper` and `@floating-ui/react-dom`.
- The SVG arrow had an additional 45-degree rotation and vertical translation on top of Radix's own arrow positioning. Removed those overrides and retained the native 10×5 triangular arrow.
- The service-specific fill selector targeted a direct SVG child, but Radix wraps its arrow in a positioning span. Target the arrow slot instead so it matches the tooltip surface.
- Mechanical styling fix; verified visually in Chrome at 1440×1000 and 390×844. The tip now aligns with the error icon and the triangle matches the surface.

## Empty services

- Add a bordered, centered “No services connected” panel with a short instruction. Preserve the header Connect action and existing permission guard; read-only users are directed to an administrator.
- Red: new close-picker test failed because the empty-state heading was absent.
- An initial placement of Connect inside the empty state broke focus restoration after saving the first service. Kept the action in the header; existing focus test passes.
- Green: 58 frontend tests across service credentials, onboarding, scoped services and admin journey. Typecheck and ESLint passed.
- Inspected the empty page in Chrome at desktop and mobile sizes; modal reopening works.
- Root completion checks passed: format, warnings-as-errors compilation, strict Credo, all 3,790 backend tests, and unused-dependency check.
