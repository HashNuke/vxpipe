# Bundled service favicons

## Scope and decisions

- Replace initials, general brand logos and icon-library marks for built-in AI and
  telephony integrations with favicons declared in their official landing HTML.
- Prefer vector SVG, otherwise the largest declared raster favicon/touch icon or
  the largest icon in a web manifest linked from that HTML. Preserve source bytes.
- Google AI Studio uses aistudio.google.com, not the generic Google G mark.
- MorseCode API has no declared favicon; use the neutral Plug placeholder, as
  explicitly requested. The same placeholder handles image-load errors.
- Bundle assets in Console React and record each exact source in the asset README.
  The shared component covers connected lists, directories, setup and dialogs.
- Use neutral framing so service colors stay faithful and black transparent marks
  remain visible in dark mode. Remove fabricated gradient backgrounds.

## Research and barriers

- Downloaded all eleven available registered-provider favicons other than OpenAI,
  plus the legacy Vertex AI inventory icon from its Google Cloud landing page.
- Telnyx favicon.ico is actually a 750px PNG. The local extension matches its bytes.
- Deepgram's ICO declares 16px in HTML but contains frames up to 64px. DeepSeek's
  ICO contains a 225px frame. Rime explicitly declares its 512px profile-named file
  as rel=icon; this is not a substituted social image.
- OpenAI's homepage declares favicon.svg, a 48px ICO and a 180px Apple icon. Curl
  and headless Chrome receive Cloudflare verification. A regular Chrome tab was
  briefly used to read the declarations; user asked to use headless only, which
  is now followed. No CAPTCHA was solved. Requested exact SVG text from the user.

## Verification

- Added the bundled-favicon/neutral-placeholder contract test first; confirmed red
  for missing Deepgram image. Vite may inline small SVGs, so the assertion accepts
  data:image sources as well as bundled asset paths; remote URLs remain excluded.
- TypeScript passes. Desktop AI listing and mobile telephony listing rendered in
  headless Chrome; each downloaded favicon displays, and MorseCode is neutral.
- OpenAI was temporarily rendered with the same placeholder while awaiting the
  official SVG. User supplied a browser download; restored the OpenAI image
  contract first and confirmed it failed, then copied the SVG byte-for-byte and
  wired the import. Its existing color-scheme styles remain intact.
- Production esbuild initially failed on the two ICO imports. Added the .ico file
  loader, then the production asset build passed. No application backend changed.
- TypeScript, static Storybook build and all 899 frontend tests (118 files) passed
  before the final OpenAI import. Final focused checks and umbrella results follow.

## Final asset checkpoint

- OpenAI source and bundled file compare byte-for-byte. All SVGs parse and contain
  no scripts, event handlers, foreign objects or external asset references.
- Final TypeScript and focused service tests pass (7 tests). Production esbuild
  passes with all assets, including the OpenAI SVG and original ICO files.
- Headless Chrome confirms every registered icon loads from the local bundle,
  with Deepgram selecting the 64px ICO frame and DeepSeek its 225px frame. Reviewed
  light/dark desktop AI listings, mobile AI and telephony lists, and the placeholder.
- Design review: original favicon colors remain intact against neutral frames;
  small icons stay legible, unknown icons use one neutral fallback, and there are
  no remote favicon dependencies. Deterministic style hook reported no findings.
- Required umbrella checks pass: mix format --check-formatted, compile with
  warnings as errors, strict Credo, 4,470 tests with zero failures (156 excluded),
  and the unused-dependency check. Final git diff --check is clean. Storybook
  remains available on port 6006; all task-owned headless browser sessions closed.

## Padding refinement and commit review

- Removed the 2px padding from `.service-logo-image` at the user's request.
  Headless Chrome at 1440px and 390px confirms loaded icons with computed 0px
  padding. The bundled assets, sizing, and fallback are unchanged.
- Reviewed the favicon checkpoint independently from the directory prototype:
  imports, missing-image fallback, ICO loader/type declaration, source provenance,
  and the focused bundled-icon test belong together. No backend contract changes.
