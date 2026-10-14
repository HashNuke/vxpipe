# Tenant context and page headings

## Changes

- Added the existing Building2 workspace icon (15px, decorative) beside tenant names on the standalone Services and API Keys pages.
- The setup stylesheet was overriding workspace titles to 20px. Include setup headings in the shared navigation heading selector: 24px desktop / 22px mobile, weight 650, line-height 1.3 and the same letter spacing. Match heading bottom spacing too.
- Replace the separate back control and tenant line on API key creation with “tenant › API Keys › New API Key”. The API Keys crumb returns to the inventory and is disabled while submitting. The current page has aria-current.
- API key views own their tenant context so both standalone stories and the navigation journey avoid a duplicated tenant label.

## Verification

- Icon and heading changes are mechanical styling; inspected both Services and API Keys at 1440×1000 and 390×844 in Chrome. Computed Services heading size is 24px, weight 650 and line-height 31.2px on desktop.
- Breadcrumb red: the updated focused return-navigation test failed because the breadcrumb was missing. Implementation preserves Cancel and returns through the crumb without submitting.
- Browser verified the creation breadcrumbs on desktop/mobile and return to the list.
- An overly broad conditional edit initially hid legacy setup steps on the keys view; restored the original legacy step condition and reran the focused suite.
- Tenant breadcrumb opens the dashboard in the application and standalone Storybook. Calls filter now aligns its label and searchable input on one compact row. Call Specs no longer displays the redundant ID column; unnamed specs use “Untitled call spec”.
- Browser checked Calls and Call Specs at desktop/mobile widths; tables retain horizontal scrolling.
- Final checks: 73 focused frontend tests, TypeScript and ESLint passed. All five root gates passed, including 3,790 backend tests.
