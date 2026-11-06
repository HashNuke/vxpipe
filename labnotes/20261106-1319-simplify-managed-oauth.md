# Simplify managed OAuth

- User clarified scope: hide unnecessary fields specifically for CIMD and DCR; preserve manual configuration for other authentication types.
- Reused setup and skill context already loaded in this checkout. Preserved all earlier uncommitted work.
- Reviewed MCP 2025-11-25 authorization/discovery and RFC 7591. Discovery supplies endpoints; Vxpipe owns client metadata, resource/scopes handling and generated protocol values. DCR can require a user-supplied initial access token, so that masked optional input remains.
- Removed managed-flow endpoint/scopes and additional-parameter disclosures, DCR registration URL and arbitrary registration parameters. Kept the underlying draft fields for manual OAuth and discovery.
- Four new tests failed before implementation: two field-visibility contracts and two transitions from invalid manual configuration to CIMD/DCR.
- Green: 100 MCP Storybook tests passed. Adapted discovery tests to inspect/edit defaults after explicitly selecting Own client; managed methods no longer expose those inputs.
- TypeScript caught a now-redundant Custom headers condition after narrowing the outer disclosure to custom methods. Removed the redundant inner guard.
- Verification in progress: TypeScript recheck, browser views for CIMD/DCR, full frontend and required umbrella checks.
- TypeScript and focused ESLint passed. All 120 frontend test files passed (927 tests); after simplifying redundant JSX, the two directly affected test files passed again (21 tests).
- Browser inspection passed for both CIMD and DCR at desktop and 390x844 mobile: CIMD has no extra settings; DCR has only the masked optional initial registration token. Manual OAuth controls remain available when selected.
- Root formatting, warnings-as-errors compilation and strict Credo passed. Full umbrella tests are still running. git diff --check passed.
- Completion: full umbrella mix test passed, including Gateway (868 tests, zero failures) and the remaining applications. Chained mix deps.unlock --check-unused passed; command exited 0. All required completion checks passed. Final diff whitespace check passed; changes remain uncommitted.
