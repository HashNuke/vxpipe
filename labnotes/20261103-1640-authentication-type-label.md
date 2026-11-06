# Authentication Type label

- Renamed the single custom MCP authentication selector to Authentication Type. Section/tab titles remain Authentication; no second selector was introduced.
- Updated existing accessible-label test queries and the UI documentation. Preserved earlier uncommitted changes.
- Mechanical copy change; no initial red test required. Reused setup completed in this checkout.
- All 90 MCP story tests passed; desktop/mobile browser inspection confirms the requested label.
- Formatting, warnings-as-errors compilation, and strict Credo passed. Umbrella mix test is still running; Call Engine reported a command_timeout in Speech.DeadlineTest at line 30. The entire focused file passed on rerun (14 tests). No backend code was changed. Remaining umbrella result and unused-dependency check pending.
- Follow-up request proposes URL-triggered authentication discovery. Current discovery is simulated after Connect; clarified whether to build a Storybook interaction or real discovery before implementing this separate scope.
