# React Flow attribution contrast

- The installed React Flow attribution is a text link, not an image. Its default
  grey text (#999) was rendered on translucent white over the dark canvas,
  producing the apparent blank grey rectangle.
- Set the supported attribution background variable to the Console background
  token and the link color to muted foreground. Preserve the original link,
  bottom-right placement and attribution content. No behavior or dependency change.
- Chrome verification: dark at 1440px and light at 390px show readable attribution.
  Computed bounds place it exactly at the canvas right/bottom edges; its original
  attribution URL remains intact. Screenshots inspected after the change.
- Storybook production build and root formatting, compilation with warnings as
  errors, strict Credo and unused dependency checks passed. Required umbrella test
  run again encountered the existing Ortex macOS native-loader error (mis-aligned
  LINKEDIT string pool); stopped after confirming that limitation.
- CSS-only change: no new automated tests. Storybook remains on port 6006 and no
  commits were requested. Prior and unrelated work was preserved.
