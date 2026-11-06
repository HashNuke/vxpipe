# Custom header label

- Renamed the authentication option to Custom headers; the shared label also updates saved-connection summaries.
- Existing name/value rows, Add header and Remove header controls already support multiple headers. Existing validation requires at least one header. No behavior change was needed.
- Preserved the earlier uncommitted single-dropdown work. Updated its option-label assertion and the relevant UI documentation.
- Mechanical copy edit; initial red test omitted. Reused setup completed earlier in this checkout.
- Follow-up: removed the generic explanatory paragraphs beneath Authentication for automatic discovery, no authentication, CIMD, and DCR; configuration fields remain available.
- Verification: 90 MCP story tests passed; Console TypeScript check passed. Browser inspection confirmed two editable header name/value pairs at desktop and mobile sizes, and DCR displays settings without its explanatory paragraph.
- Umbrella checks passed: formatting, warnings-as-errors compilation, strict Credo, full mix test (seed 648454), and unused dependency check. Gateway/media tests account for most of the runtime.
- git diff --check passed. No commits created.
