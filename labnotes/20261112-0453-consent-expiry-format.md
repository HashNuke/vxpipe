# Consent expiry format

The confirmation receipt now formats expiry as `12 Dec 2026, 10:21am`:
zero-padded day, abbreviated English month, year, 12-hour time and lowercase
am/pm without seconds. It keeps the browser's local timezone and the original
machine-readable datetime value.

This is a presentation-only change. All eight existing focused OAuthConsent
cases pass; changed-file ESLint, the production TypeScript/assets build and root
format/compilation/Credo/unused-dependency checks pass. No new tests or full suite
were added. Real Chrome inspection of the production bundle confirmed the exact
requested example on desktop and `01 Dec 2026, 9:05pm` on mobile, without wrapping
or overflow. Synthetic receipt fixtures used no accounts or grants; the temporary
server, browser and files were cleaned up. No environment files were read.

Deployed the rebuilt release to Vitrum. The publicly served fingerprinted OAuth
bundle matches the verified build, health returns ok, and both services are active.
