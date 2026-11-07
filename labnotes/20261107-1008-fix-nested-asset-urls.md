# Fix nested-page asset URLs

Authenticated cold-directory-outage browser acceptance exposed missing bundled
native logos. The built JavaScript exports relative file-loader URLs, such as
`./cartesia-7MJLORDY.svg`, which resolve beneath the current nested tenant route.

Astra independently reproduced the actual browser boundary without navigating the
parent's session: the relative URL returns HTML and the Image fires error with
naturalWidth zero; `/assets/cartesia-7MJLORDY.svg` returns SVG and loads at 416×426.
The committed esbuild profile and ServiceLogo source match the browser checkout.
This is project build configuration, not an outage fixture failure.

Add a focused Console-owned build regression that imports the real bundled SVG
using the configured asset-loader flags, executes the emitted JavaScript to obtain
its URL, and checks that a nested tenant page resolves it under the served assets
mount. Preserve the emitted image bytes. Obtain the failing result before changing
the shared build profile; then rebuild and inspect actual desktop/mobile rendering.

The new regression fails for the expected resolved-path mismatch: the emitted URL
resolves beneath `/t/tenant/services/` instead of `/assets/`. Adding the shared
`--public-path=/assets` flag makes it pass while preserving the actual image bytes.
The clean focused Console run passes one test; the existing ServiceLogo and
IntegrationsDirectory frontend group passes all 13 tests. All five root gates are
running. Rebuilt the isolated browser checkout using the same configuration fix;
restart its owned Console/peer before rendering verification. Retained the same
fixture endpoint and private bearer credential across that restart so the already
verified saved connection stays meaningful.

The rebuilt authenticated cold-outage AI page now decodes all ten supplied native
logos at desktop (1280×900) and mobile (390×844); each resolves under `/assets/`
with positive naturalWidth. MorseCode uses its intended placeholder. Both rendered
screenshots were inspected with no horizontal overflow. Astra reviewed the actual
configuration/test/documentation diff and found no additional issue; its approval
explicitly scopes the automated regression to the real SVG build boundary, with
these browser checks supplying image decoding evidence. Full root gates remain
in progress. No speech or source-cutover state machine changed; Lean is inapplicable.

The complete root run finishes with 4,992 tests, one failure and 263 exclusions.
All 548 Console tests pass, including the asset regression; format, compilation,
strict Credo and unused-dependency gates pass. The failure is a Persistence archive
subscriber monitor assertion (`:noproc` rather than `:normal`) and is tracked in
[its own investigation](20261107-1028-stabilize-archive-monitor.md). The milestone's
full-root gate remains open while that reproduced failure is investigated.
