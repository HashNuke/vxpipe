# Shared copy button

Replaced all five console clipboard implementations with `admin/CopyButton`: Telnyx webhook URLs, MCP callback fields, both API-key reveal screens, and call-spec JSON. The component uses the existing console Button and owns clipboard state, a two-second success reset, a check icon, and manual-copy failure feedback. Original labels return after success; CSS reserves both label widths to prevent layout shifts. Removed duplicate success messages, per-screen timers, and unused styling. Added shared Storybook examples and usage guidance.

The value keys the internal control, so an in-flight copy cannot confirm a subsequently changed value. Pending requests disable repeated clicks; unmounting cancels the reset and ignores late clipboard completion. No dependencies were added.

Verification:
- Red: existing source-view tests failed because the JSON action did not show Copied and reported failures through a separate toast.
- Green: 40 focused tests across CopyButton, ScopedServicesStory, TelnyxConnectionDialog, McpSetupInformation, and source-view error surfaces passed. Includes exact JSON preservation, repeat-copy timing, failure recovery, and a changed value during a pending copy.
- TypeScript and focused ESLint passed; diff whitespace check passed.
- Headless Chrome inspected the shared action at desktop width, the real inherited Telnyx modal at 390px, and light-theme failure feedback. Copy and Copied both measured 97.796875px; the label returned to Copy; no mobile horizontal overflow.
- Browser clipboard success/failure used a local stub because headless clipboard permission was denied. Tests independently verify the exact clipboard value. Preview runs from an environment-free mirror; no environment files or live telephony tests were used.

The Telnyx v2/cost-webhook request remains a separate checkpoint. These UI changes are not yet deployed to Vitrum.
